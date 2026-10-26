#import <AppKit/AppKit.h>

// Launch the installed, unmodified Moonlight with the SDL backend verified on
// this Mac. No shell, global environment changes, or virtual-HID entitlement.
static void showError(NSString *message) {
    NSAlert *alert=[NSAlert new];
    alert.messageText=@"Moonlight for 8BitDo";
    alert.informativeText=message;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSURL *moonlight=[NSURL fileURLWithPath:@"/Applications/Moonlight.app"];
    if(![[NSFileManager defaultManager] fileExistsAtPath:moonlight.path]){
        showError(@"Moonlight was not found in Applications.");return 1;
    }
    if([NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.moonlight-stream.Moonlight"].count){
        showError(@"Quit Moonlight, then open this shortcut again so the controller-compatible input backend is selected.");return 1;
    }
    NSTask *start=[NSTask new];
    start.executableURL=[NSURL fileURLWithPath:@"/bin/launchctl"];
    start.arguments=@[@"kickstart",[NSString stringWithFormat:@"gui/%u/com.zbreilly.ReceiverBridge.agent",getuid()]];
    start.standardOutput=[NSFileHandle fileHandleWithNullDevice];
    start.standardError=[NSFileHandle fileHandleWithNullDevice];
    NSError *taskError=nil;
    if(![start launchAndReturnError:&taskError]){
        showError(@"Could not contact the background controller service. Run Install.command from the ReceiverBridge package.");return 1;
    }
    [start waitUntilExit];
    if(start.terminationStatus!=0){
        // kickstart without -k may report already running; inspect registration.
        NSTask *check=[NSTask new];check.executableURL=start.executableURL;
        check.arguments=@[@"print",start.arguments.lastObject];
        check.standardOutput=[NSFileHandle fileHandleWithNullDevice];
        check.standardError=[NSFileHandle fileHandleWithNullDevice];
        if(![check launchAndReturnError:&taskError])return 1;
        [check waitUntilExit];
        if(check.terminationStatus!=0){
            showError(@"The background controller service is not registered. Run Install.command from the ReceiverBridge package.");return 1;
        }
    }
    NSWorkspaceOpenConfiguration *configuration=[NSWorkspaceOpenConfiguration configuration];
    configuration.environment=@{@"SDL_JOYSTICK_HIDAPI_XBOX":@"0",@"SDL_JOYSTICK_MFI":@"1"};
    __block BOOL done=NO;__block int result=0;
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:moonlight configuration:configuration
        completionHandler:^(NSRunningApplication *application,NSError *error){
            (void)application;
            if(error){showError(error.localizedDescription);result=1;}
            done=YES;
        }];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:30];
    while(!done&&deadline.timeIntervalSinceNow>0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
    return done?result:1;
}}
