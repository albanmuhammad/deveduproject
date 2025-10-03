({
    handleRefresh : function(component, event, helper) {
        // Refresh halaman record agar related list ikut update
        $A.get('e.force:refreshView').fire();
    },
    handleSaved : function(component, event, helper) {
        // Pastikan refresh terpanggil, lalu tutup Quick Action
        $A.get('e.force:refreshView').fire();
        $A.get('e.force:closeQuickAction').fire();
    }
})