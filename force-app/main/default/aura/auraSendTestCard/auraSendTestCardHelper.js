({
    sendEmail: function (component, event, helper) {
        var recId = component.get("v.recordId");
        var action = component.get("c.sendTestCardEmail");
        action.setParams({ "oppId": recId });

        action.setCallback(this, function (response) {
            var state = response.getState();
            console.log("⚡ state=" + state);

            let toastTitle, toastType, toastMsg;

            if (state === "SUCCESS") {
                var result = response.getReturnValue();
                console.log("⚡ result=" + result);

                if (result === "success") {
                    toastTitle = "Success";
                    toastType = "success";
                    toastMsg = "Test Card email sent successfully.";
                } else {
                    toastTitle = "Error";
                    toastType = "error";
                    toastMsg = result;
                }
            } else {
                var errors = response.getError();
                var msg = (errors && errors[0] && errors[0].message) ? errors[0].message : "Unknown error";
                console.error("⚡ Apex ERROR: " + msg);

                toastTitle = "Error";
                toastType = "error";
                toastMsg = msg;
            }

            // Hide spinner
            helper.hideSpinner(component);

            // Show toast
            helper.showToast(toastTitle, toastType, toastMsg);

            // Close quick action + refresh view
            document.activeElement.blur();
            $A.get("e.force:closeQuickAction").fire();
            $A.get("e.force:refreshView").fire();
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

    showSpinner : function(component) {
        var spinner = component.find("spinner");
        $A.util.removeClass(spinner, "slds-hide");
        $A.util.addClass(spinner, "slds-show");
    },

    hideSpinner : function(component) {
        var spinner = component.find("spinner");
        $A.util.removeClass(spinner, "slds-show");
        $A.util.addClass(spinner, "slds-hide");
    }
})
