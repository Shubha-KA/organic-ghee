const { DefaultAzureCredential } = require("@azure/identity");
const { QueueClient } = require("@azure/storage-queue");

function getQueueClient() {
    const accountName = process.env.STORAGE_ACCOUNT_NAME;
    const queueName = process.env.ORDER_NOTIFICATIONS_QUEUE || "order-notifications";
    if (!accountName) {
        throw new Error("STORAGE_ACCOUNT_NAME is required for notifications.");
    }

    return new QueueClient(
        `https://${accountName}.queue.core.windows.net/${queueName}`,
        new DefaultAzureCredential()
    );
}

async function enqueueNotification(message) {
    const encodedMessage = Buffer.from(JSON.stringify(message)).toString("base64");
    await getQueueClient().sendMessage(encodedMessage);
}

module.exports = { enqueueNotification };
