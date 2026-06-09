const { app } = require("@azure/functions");
const { DefaultAzureCredential } = require("@azure/identity");

async function sendMail(message, context) {
    const senderUserId = process.env.NOTIFICATION_SENDER_USER_ID;
    const contactRecipient = process.env.CONTACT_NOTIFICATION_RECIPIENT;
    const recipient = message.type === "contact" ? contactRecipient : message.recipient;

    if (!senderUserId || !recipient) {
        context.warn("Notification sender or recipient is not configured; message was not sent.");
        return;
    }

    const credential = new DefaultAzureCredential();
    const token = await credential.getToken("https://graph.microsoft.com/.default");
    const isContact = message.type === "contact";

    const subject = isContact
        ? `Contact request: ${message.subject || "Organic Ghee website"}`
        : `Order confirmation ${message.orderId}`;
    const content = isContact
        ? `From: ${message.name} <${message.email}>\n\n${message.message}`
        : `Hello ${message.customerName}, your order for ${message.quantity} x ${message.dishName} has been received.`;

    const response = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(senderUserId)}/sendMail`, {
        method: "POST",
        headers: {
            Authorization: `Bearer ${token.token}`,
            "Content-Type": "application/json"
        },
        body: JSON.stringify({
            message: {
                subject,
                body: { contentType: "Text", content },
                toRecipients: [{ emailAddress: { address: recipient } }]
            },
            saveToSentItems: true
        })
    });

    if (!response.ok) {
        throw new Error(`Microsoft Graph sendMail failed with status ${response.status}: ${await response.text()}`);
    }
}

app.storageQueue("orderNotifications", {
    queueName: "order-notifications",
    connection: "OrderNotifications",
    handler: async (queueItem, context) => {
        const message = typeof queueItem === "string" ? JSON.parse(queueItem) : queueItem;
        await sendMail(message, context);
    }
});
