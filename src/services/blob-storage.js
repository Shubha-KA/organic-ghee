const crypto = require("crypto");
const { DefaultAzureCredential } = require("@azure/identity");
const { BlobServiceClient } = require("@azure/storage-blob");

function getContainerClient() {
    const accountName = process.env.STORAGE_ACCOUNT_NAME;
    const containerName = process.env.BLOB_CONTAINER || "appblob";
    if (!accountName) {
        throw new Error("STORAGE_ACCOUNT_NAME is required for image uploads.");
    }

    const serviceClient = new BlobServiceClient(
        `https://${accountName}.blob.core.windows.net`,
        new DefaultAzureCredential()
    );
    return serviceClient.getContainerClient(containerName);
}

async function uploadDishImage(file) {
    const extension = file.name.includes(".") ? file.name.slice(file.name.lastIndexOf(".")) : "";
    const blobName = `${crypto.randomUUID()}${extension}`;
    const blobClient = getContainerClient().getBlockBlobClient(blobName);

    await blobClient.uploadData(file.data, {
        blobHTTPHeaders: {
            blobContentType: file.mimetype || "application/octet-stream"
        }
    });

    return { name: blobName, url: blobClient.url };
}

async function deleteDishImage(blobName) {
    if (!blobName) {
        return;
    }
    await getContainerClient().deleteBlob(blobName, { deleteSnapshots: "include" });
}

module.exports = { deleteDishImage, uploadDishImage };
