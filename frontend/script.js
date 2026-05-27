// ========================================
// FEEDBACK FORM SCRIPT
// Sends feedback submissions to the
// Azure Function API endpoint.
// ========================================

const feedbackForm = document.getElementById("feedbackForm");

feedbackForm.addEventListener("submit", async (event) => {

    event.preventDefault();

    // ========================================
    // READ USER INPUT
    // ========================================

    const message = document.getElementById("feedbackMessage").value;

    // ========================================
    // SEND DATA TO API
    // ========================================

    const response = await fetch("http://localhost:7071/api/feedback", {

        method: "POST",

        headers: {
            "Content-Type": "application/json"
        },

        body: JSON.stringify({
            message: message
        })
    });

    // ========================================
    // PROCESS API RESPONSE
    // ========================================

    const result = await response.json();

    document.getElementById("feedbackStatus").innerText =
        result.message;

    // ========================================
    // CLEAR FORM
    // ========================================

    feedbackForm.reset();
});
