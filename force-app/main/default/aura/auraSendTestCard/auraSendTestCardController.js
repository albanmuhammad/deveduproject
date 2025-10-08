({
    doInit : function(component, event, helper) {
        helper.showSpinner(component);
        helper.sendEmail(component, event, helper);
    }
})