({
    generateCard: function (component, event, helper) {
        var recId = component.get("v.recordId");
        var action = component.get("c.createTestCardPdf");
        action.setParams({ "oppId": recId });

        action.setCallback(this, function (response) {
            var state = response.getState();
            console.log("⚡ state=" + state);

            let toastTitle, toastType, toastMsg;

            if (state === "SUCCESS") {
                var result = response.getReturnValue();
                console.log("⚡ result=" + result);

                if (result === "File Created Success") {
                    toastTitle = "Success";
                    toastType = "success";
                    toastMsg = "Test Card generated successfully.";
                } else if (result === "File Updated Success") {
                    toastTitle = "Success";
                    toastType = "success";
                    toastMsg = "Test Card updated successfully.";
                } else if (result === "Pas foto 3x4 must be verified before generating test card") {
                    // Validation error for pas foto
                    toastTitle = "Validation Error";
                    toastType = "warning";
                    toastMsg = "Pas foto 3x4 must be verified before generating test card.";
                } else if (result.startsWith("Error:")) {
                    toastTitle = "Error";
                    toastType = "error";
                    toastMsg = result;
                } else {
                    toastTitle = "Info";
                    toastType = "info";
                    toastMsg = result;
                }
            } else if (state === "ERROR") {
                var errors = response.getError();
                var msg = (errors && errors[0] && errors[0].message) ? errors[0].message : "Unknown error";
                console.error("⚡ Apex ERROR: " + msg);

                toastTitle = "Error";
                toastType = "error";
                toastMsg = msg;
            }

            // 🔹 Hide spinner once Apex is done
            helper.hideSpinner(component);

            // 🔹 Show toast
            helper.showToast(toastTitle, toastType, toastMsg);

            // 🔹 Only close quick action and refresh if successful
            if (toastType === "success") {
                document.activeElement.blur(); // avoid aria-hidden warning
                $A.get("e.force:closeQuickAction").fire();
                $A.get("e.force:refreshView").fire();
            }
        });

        $A.enqueueAction(action);
    },

    showToast: function (title, type, message) {
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            title: title,
            type: type,
            message: message
        });
        toastEvent.fire();
    },

    // showSpinner : function(component) {
    //     var spinner = component.find("spinner");
    //     $A.util.removeClass(spinner, "slds-hide");
    //     $A.util.addClass(spinner, "slds-show");
    // },

    // hideSpinner : function(component) {
    //     var spinner = component.find("spinner");
    //     $A.util.removeClass(spinner, "slds-show");
    //     $A.util.addClass(spinner, "slds-hide");
    // }
    showSpinner : function(component) {
        component.set("v.isLoading", true);
        var spinner = component.find("spinner");
        $A.util.removeClass(spinner, "slds-hide");
        $A.util.addClass(spinner, "slds-show");
    },

    hideSpinner : function(component) {
        component.set("v.isLoading", false);
        var spinner = component.find("spinner");
        $A.util.removeClass(spinner, "slds-show");
        $A.util.addClass(spinner, "slds-hide");
    }
})