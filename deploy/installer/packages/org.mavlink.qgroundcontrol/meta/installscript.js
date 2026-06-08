function Component()
{

}

Component.prototype.createOperations = function()
{
    try {
        component.createOperations();
    } catch (e) {
        console.log(e);
    }

    if (systemInfo.productType === "windows") {
        component.addOperation("CreateShortcut", "@TargetDir@/bin/BriechUAS.exe", "@StartMenuDir@/Briech UAS.lnk");
        component.addOperation("CreateShortcut", "@TargetDir@/bin/BriechUAS.exe", "@DesktopDir@/Briech UAS.lnk");
    }
}
