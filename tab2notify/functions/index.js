const { onValueWritten, onValueCreated } = require("firebase-functions/v2/database");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.database();

/**
 * Sanitizes FCM token into a safe RTDB key (matching the Flutter app implementation)
 */
function sanitizeTokenKey(token) {
  const clean = token.replace(/[^a-zA-Z0-9]/g, "");
  if (clean.length > 40) {
    return clean.substring(clean.length - 40);
  }
  return clean.length > 0 ? clean : `tok_${Date.now()}`;
}

/**
 * Server-Side Notification Authorization Gate:
 * Cross-references candidate tokens with the centralized /device_tokens registry.
 * Validates that:
 * 1. Token exists and has active === true
 * 2. Token is assigned to the exact intended targetUserId
 * 3. Token has the exact matching targetRole ('waiter' vs 'manager')
 * 4. Token belongs to the matching managerPhone scope
 *
 * Any stale token (e.g. previous waiter who logged out, or account switched on same device)
 * is strictly filtered out and rejected.
 */
async function getAuthorizedTokens({ managerPhone, targetUserId, targetRole }) {
  const authorizedTokens = [];
  const cleanPhone = (managerPhone || "").replace(/[^0-9]/g, "");

  // 1. Retrieve candidate tokens from role-scoped path
  let candidateTokens = [];
  if (targetRole === "waiter") {
    const snap = await db.ref(`waiters/${cleanPhone}/${targetUserId}/fcmTokens`).get();
    if (snap.exists()) {
      const data = snap.val();
      Object.values(data).forEach((entry) => {
        if (entry && entry.token && entry.active === true) {
          candidateTokens.push(entry.token.trim());
        }
      });
    }
  } else if (targetRole === "manager") {
    const snap = await db.ref(`users/${targetUserId}/fcmTokens`).get();
    if (snap.exists()) {
      const data = snap.val();
      Object.values(data).forEach((entry) => {
        if (entry && entry.token && entry.active === true) {
          candidateTokens.push(entry.token.trim());
        }
      });
    }
  }

  // 2. Perform Server-Side Authorization against Centralized Device Registry (/device_tokens)
  for (const token of candidateTokens) {
    const tokenKey = sanitizeTokenKey(token);
    const deviceSnap = await db.ref(`device_tokens/${tokenKey}`).get();

    if (!deviceSnap.exists()) {
      console.warn(`[AUTH REJECT] Token ${tokenKey} missing from /device_tokens registry. Skipping.`);
      continue;
    }

    const deviceData = deviceSnap.val();

    // Check 1: Is the token marked currently active?
    if (deviceData.active !== true) {
      console.warn(`[AUTH REJECT] Token ${tokenKey} is inactive/logged out. Suppressing notification.`);
      continue;
    }

    // Check 2: Does the device token match the intended user ID?
    if (deviceData.userId !== targetUserId) {
      console.warn(
        `[AUTH REJECT] Device token ${tokenKey} has been reassigned to user ${deviceData.userId}, but target is ${targetUserId}. Suppressing.`
      );
      continue;
    }

    // Check 3: Does the device token match the intended role?
    if (deviceData.role !== targetRole) {
      console.warn(
        `[AUTH REJECT] Device token ${tokenKey} role mismatch (device: ${deviceData.role}, target: ${targetRole}). Suppressing.`
      );
      continue;
    }

    // Check 4: Manager phone scope isolation
    const deviceManagerPhone = (deviceData.managerPhone || "").replace(/[^0-9]/g, "");
    if (cleanPhone && deviceManagerPhone && cleanPhone !== deviceManagerPhone) {
      console.warn(`[AUTH REJECT] Manager phone scope mismatch for token ${tokenKey}. Suppressing.`);
      continue;
    }

    // Token passed all authorization checks
    authorizedTokens.push(token);
  }

  return authorizedTokens;
}

/**
 * Automatically purges stale/unregistered FCM tokens returned by Firebase Messaging
 */
async function pruneInvalidTokens(tokens, responses, cleanPhone, targetUserId, targetRole) {
  for (let i = 0; i < responses.length; i++) {
    const res = responses[i];
    if (!res.success && res.error) {
      const errorCode = res.error.code;
      if (
        errorCode === "messaging/invalid-registration-token" ||
        errorCode === "messaging/registration-token-not-registered"
      ) {
        const deadToken = tokens[i];
        const tokenKey = sanitizeTokenKey(deadToken);
        console.log(`[DEAD TOKEN CLEANUP] Pruning unregistered FCM token ${tokenKey}`);

        await db.ref(`device_tokens/${tokenKey}`).remove();
        if (targetRole === "waiter" && cleanPhone && targetUserId) {
          await db.ref(`waiters/${cleanPhone}/${targetUserId}/fcmTokens/${tokenKey}`).remove();
        } else if (targetRole === "manager" && targetUserId) {
          await db.ref(`users/${targetUserId}/fcmTokens/${tokenKey}`).remove();
        }
      }
    }
  }
}

/**
 * Cloud Function Trigger: Listen to Table Status updates (/tables/{managerPhone}/{tableId})
 * When customer or ESP32 triggers Table Pending (flag === 0):
 * 1. Identifies the assigned waiter
 * 2. Authorizes target device tokens server-side
 * 3. Dispatches FCM push alert exclusively to the active waiter's device
 * 4. Ensures MANAGER never receives this notification unless unassigned/escalated
 * 5. After strictly 20 seconds, if request is still pending, escalates to the Manager
 */
exports.onTableRequestTriggered = onValueWritten(
  "tables/{managerPhone}/{tableId}",
  async (event) => {
    const afterData = event.data.after.val();
    const beforeData = event.data.before.val();

    if (!afterData) return; // Table deleted

    // Trigger only when flag becomes 0 (Urgent Request) and previously was not 0
    const isNowPending = afterData.flag === 0 || afterData.status === "pending";
    const wasPending = beforeData ? beforeData.flag === 0 || beforeData.status === "pending" : false;

    if (!isNowPending || wasPending) {
      return;
    }

    const { managerPhone, tableId } = event.params;
    const cleanPhone = (managerPhone || "").replace(/[^0-9]/g, "");
    const tableNumber = afterData.table_number || parseInt(tableId.replace(/[^0-9]/g, ""), 10) || 1;

    // Resolve assigned waiter ID strictly from database record
    let assignedWaiterId = (afterData.assigned_waiter_id || "").trim();
    if (!assignedWaiterId && afterData.waiter_name) {
      const match = String(afterData.waiter_name).match(/\(([^)]+)\)/);
      if (match && match[1]) {
        assignedWaiterId = match[1].trim();
      }
    }

    if (!assignedWaiterId) {
      console.log(`[FCM SERVER] Table ${tableNumber} has no assigned waiter. Skipping waiter push.`);
      return;
    }

    console.log(
      `[FCM SERVER] Table ${tableNumber} Calling -> Authorizing tokens for Waiter ${assignedWaiterId} under Manager ${cleanPhone}`
    );

    // Retrieve authorized tokens
    const tokens = await getAuthorizedTokens({
      managerPhone: cleanPhone,
      targetUserId: assignedWaiterId,
      targetRole: "waiter",
    });

    if (tokens.length === 0) {
      console.log(`[FCM SERVER] No active authorized tokens found for Waiter ${assignedWaiterId}. Push skipped.`);
      return;
    }

    // Build High-Priority Waiter Notification Payload
    const message = {
      tokens,
      notification: {
        title: `🛎️ Table ${tableNumber} Calling!`,
        body: `Customer requested immediate assistance at Table ${tableNumber} 🔴`,
      },
      data: {
        requestId: tableId,
        tableNumber: String(tableNumber),
        targetRole: "waiter",
        targetUserId: assignedWaiterId,
        waiterId: assignedWaiterId,
        managerPhone: cleanPhone,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "waiter_requests_channel",
          priority: "max",
          sound: "incoming_prompt",
          defaultVibrateTimings: true,
          visibility: "public",
        },
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title: `🛎️ Table ${tableNumber} Calling!`,
              body: `Customer requested immediate assistance at Table ${tableNumber} 🔴`,
            },
            sound: "Incoming_Prompt.mp3",
            badge: 1,
            critical: true,
          },
        },
      },
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);
      console.log(
        `[FCM SERVER] Dispatched to Waiter ${assignedWaiterId}: ${response.successCount} succeeded, ${response.failureCount} failed.`
      );

      // Clean up any dead/unregistered tokens automatically
      if (response.failureCount > 0) {
        await pruneInvalidTokens(tokens, response.responses, cleanPhone, assignedWaiterId, "waiter");
      }
    } catch (err) {
      console.error(`[FCM SERVER ERROR] Multicast failed:`, err);
    }

    // -------------------------------------------------------------
    // 20-Second Manager Escalation Timer
    // If request remains pending for >20 seconds, alert the manager
    // -------------------------------------------------------------
    setTimeout(async () => {
      try {
        const latestSnap = await db.ref(`tables/${cleanPhone}/${tableId}`).get();
        if (!latestSnap.exists()) return;

        const latestData = latestSnap.val();
        const isStillPending = latestData.flag === 0 || latestData.status === "pending";

        if (!isStillPending) {
          console.log(`[FCM ESCALATION] Table ${tableNumber} was attended/accepted within 20s. Escalation cancelled.`);
          return;
        }

        console.log(`[FCM ESCALATION] Table ${tableNumber} remained unattended for >20s! Escalating to manager ${cleanPhone}...`);

        const managerUid = latestData.manager_uid || "";
        const waiterDisplayName = latestData.waiter_name || latestData.assigned_waiter_name || assignedWaiterId || "Unassigned";

        // Retrieve authorized manager tokens
        let managerTokens = [];
        if (managerUid) {
          managerTokens = await getAuthorizedTokens({
            managerPhone: cleanPhone,
            targetUserId: managerUid,
            targetRole: "manager",
          });
        }

        // Fallback: search users registry for manager matching this phone
        if (managerTokens.length === 0) {
          const usersSnap = await db.ref("users").get();
          if (usersSnap.exists()) {
            const usersData = usersSnap.val();
            for (const [uid, uData] of Object.entries(usersData)) {
              const uPhone = (uData.phone || uData.phoneNumber || "").replace(/[^0-9]/g, "");
              if (uPhone === cleanPhone && (uData.role === "manager" || !uData.role)) {
                const foundTokens = await getAuthorizedTokens({
                  managerPhone: cleanPhone,
                  targetUserId: uid,
                  targetRole: "manager",
                });
                if (foundTokens.length > 0) {
                  managerTokens = foundTokens;
                  break;
                }
              }
            }
          }
        }

        if (managerTokens.length === 0) {
          console.log(`[FCM ESCALATION] No active authorized tokens found for Manager ${cleanPhone}. Escalation push skipped.`);
          return;
        }

        const escalationMessage = {
          tokens: managerTokens,
          notification: {
            title: `⚠️ Unattended Table ${tableNumber} Alert!`,
            body: `Table ${tableNumber} (Waiter: ${waiterDisplayName}) has been pending for >20s!`,
          },
          data: {
            requestId: tableId,
            tableNumber: String(tableNumber),
            targetRole: "manager",
            type: "manager_escalation",
            managerPhone: cleanPhone,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
          android: {
            priority: "high",
            notification: {
              channelId: "manager_escalation_channel",
              priority: "max",
              sound: "please_hold",
              defaultVibrateTimings: true,
              visibility: "public",
            },
          },
          apns: {
            payload: {
              aps: {
                alert: {
                  title: `⚠️ Unattended Table ${tableNumber} Alert!`,
                  body: `Table ${tableNumber} (Waiter: ${waiterDisplayName}) has been pending for >20s!`,
                },
                sound: "Please_Hold.mp3",
                badge: 1,
                critical: true,
              },
            },
          },
        };

        const escResponse = await admin.messaging().sendEachForMulticast(escalationMessage);
        console.log(`[FCM ESCALATION] Manager push sent: ${escResponse.successCount} succeeded, ${escResponse.failureCount} failed.`);
      } catch (escErr) {
        console.error(`[FCM ESCALATION ERROR] Failed to run manager escalation:`, escErr);
      }
    }, 20000);
  }
);

/**
 * Cloud Function Trigger: Listen to targeted notification requests (/notifications_queue/{queueId})
 * Allows explicit targeting:
 * - targetRole: 'manager' -> sends strictly to verified active manager tokens
 * - targetRole: 'waiter' -> sends strictly to verified active tokens for targetWaiterId
 */
exports.onNotificationQueueCreated = onValueCreated(
  "notifications_queue/{queueId}",
  async (event) => {
    const queueData = event.data.val();
    if (!queueData) return;

    const { queueId } = event.params;
    const { targetRole, targetUserId, managerPhone, title, body, payload } = queueData;

    if (!targetRole || !targetUserId) {
      console.warn(`[NOTIF QUEUE] Missing targetRole or targetUserId in queue item ${queueId}`);
      await db.ref(`notifications_queue/${queueId}`).remove();
      return;
    }

    console.log(`[NOTIF QUEUE] Processing ${targetRole} notification for ${targetUserId}`);

    const tokens = await getAuthorizedTokens({
      managerPhone,
      targetUserId,
      targetRole,
    });

    if (tokens.length > 0) {
      const message = {
        tokens,
        notification: {
          title: title || "Notification",
          body: body || "",
        },
        data: {
          ...(payload || {}),
          targetRole,
          targetUserId,
          managerPhone: managerPhone || "",
        },
        android: {
          priority: "high",
          notification: {
            channelId: targetRole === "waiter" ? "waiter_requests_channel" : "manager_escalation_channel",
            priority: "max",
            sound: targetRole === "waiter" ? "incoming_prompt" : "please_hold",
          },
        },
      };

      try {
        const response = await admin.messaging().sendEachForMulticast(message);
        console.log(`[NOTIF QUEUE] Sent to ${tokens.length} tokens: ${response.successCount} succeeded.`);
        if (response.failureCount > 0) {
          await pruneInvalidTokens(tokens, response.responses, managerPhone, targetUserId, targetRole);
        }
      } catch (err) {
        console.error(`[NOTIF QUEUE ERROR] Send failed:`, err);
      }
    } else {
      console.log(`[NOTIF QUEUE] No authorized active tokens for ${targetRole} ${targetUserId}`);
    }

    // Clean up processed queue item
    await db.ref(`notifications_queue/${queueId}`).remove();
  }
);
