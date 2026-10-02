// ========================================
// FEEDBACK FUNCTION
// Receives feedback from the frontend,
// validates the request and stores the
// submission inside Azure Table Storage.
// ========================================

const { TableClient } = require("@azure/data-tables");

// ========================================
// APPLICATION INSIGHTS
// Only initialise custom telemetry when
// the Azure connection string is present.
// This avoids telemetry calls during local
// unit tests where App Insights is not used.
// ========================================

let telemetryClient = null;

if (
    process.env.NODE_ENV !== "test" &&
    process.env.APPLICATIONINSIGHTS_CONNECTION_STRING
) {
    const appInsights = require("applicationinsights");

    appInsights.setup();
    telemetryClient = appInsights.defaultClient;
}

module.exports = async function (context, req) {

    context.log("Feedback function triggered.");

    // ========================================
    // READ FEEDBACK MESSAGE
    // ========================================

    const feedback = req.body;

    // ========================================
    // VALIDATE REQUEST
    // ========================================

    if (
        !feedback ||
        typeof feedback.message !== "string" ||
        feedback.message.trim() === ""
    ) {

        context.res = {
            status: 400,
            body: {
                error: "Feedback message is required."
            }
        };

        return;
    }

    // ========================================
    // CONNECT TO AZURE TABLE STORAGE
    // ========================================

    const connectionString =
        process.env.FEEDBACK_STORAGE_CONNECTION;

    if (!connectionString) {
        context.log.error("FEEDBACK_STORAGE_CONNECTION is missing.");

        context.res = {
            status: 500,
            body: {
                error: "Storage configuration is missing."
            }
        };

        return;
    }

    const tableName = "FeedbackSubmissions";

    const client = TableClient.fromConnectionString(
        connectionString,
        tableName
    );

    // ========================================
    // CREATE FEEDBACK RECORD
    // ========================================

    const entity = {

        partitionKey: "feedback",

        rowKey: Date.now().toString(),

        message: feedback.message.trim(),

        submittedAt: new Date().toISOString()
    };

    // ========================================
    // SAVE TO TABLE STORAGE
    // ========================================

    await client.createEntity(entity);

    context.log("Feedback saved to table storage.");

    // ========================================
    // CUSTOM APPLICATION METRIC
    // Records one successful feedback
    // submission after storage succeeds.
    // ========================================

    if (telemetryClient) {
        telemetryClient.trackMetric({
            name: "FeedbackSubmissions",
            value: 1
        });

        context.log("FeedbackSubmissions custom metric recorded.");
    }

    // ========================================
    // RETURN SUCCESS RESPONSE
    // ========================================

    context.res = {

        status: 200,

        body: {
            message: "Feedback received successfully."
        }
    };
};