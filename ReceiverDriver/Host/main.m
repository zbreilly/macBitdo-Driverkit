#import <AppKit/AppKit.h>
#import <SystemExtensions/SystemExtensions.h>

static NSString *const driverID=@"com.zbreilly.macBitdo.DriverHost.Receiver";
static NSString *const legacyLabel=@"com.zbreilly.ReceiverBridge.agent";

@interface DriverApp : NSObject <NSApplicationDelegate,OSSystemExtensionRequestDelegate>
@property NSWindow *window;
@property NSTextField *status;
@property NSButton *activate,*deactivate,*restore;
@property BOOL removing,restoreAfterRemoval;
@end

@implementation DriverApp
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,570,260)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"macBitdo Driver";
    NSTextField *heading=[NSTextField labelWithString:@"8BitDo Ultimate 2.4 GHz — DriverKit"];
    heading.font=[NSFont boldSystemFontOfSize:19];heading.frame=NSMakeRect(25,210,520,28);
    [self.window.contentView addSubview:heading];
    self.status=[NSTextField wrappingLabelWithString:@"Activate the driver once, approve it in System Settings if asked, then close this app. macOS runs the driver when the receiver is connected. Activation stops the previous bridge to prevent a USB conflict."];
    self.status.frame=NSMakeRect(25,100,520,95);[self.window.contentView addSubview:self.status];
    self.activate=[NSButton buttonWithTitle:@"Activate Driver" target:self action:@selector(activateDriver:)];
    self.activate.frame=NSMakeRect(25,45,150,32);[self.window.contentView addSubview:self.activate];
    self.deactivate=[NSButton buttonWithTitle:@"Remove Driver" target:self action:@selector(removeDriver:)];
    self.deactivate.frame=NSMakeRect(190,45,150,32);[self.window.contentView addSubview:self.deactivate];
    self.restore=[NSButton buttonWithTitle:@"Restore Old Bridge" target:self action:@selector(restoreBridge:)];
    self.restore.frame=NSMakeRect(355,45,180,32);[self.window.contentView addSubview:self.restore];
    [self.window center];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {(void)sender;return YES;}
- (int)launchctl:(NSArray<NSString *> *)arguments {
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/bin/launchctl"];
    task.arguments=arguments;
    task.standardOutput=[NSFileHandle fileHandleWithNullDevice];
    task.standardError=[NSFileHandle fileHandleWithNullDevice];
    NSError *error=nil;if(![task launchAndReturnError:&error])return -1;
    [task waitUntilExit];return task.terminationStatus;
}
- (NSString *)legacyPlist {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/com.zbreilly.ReceiverBridge.agent.plist"];
}
- (NSString *)backupPlist {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/macBitdo Driver/ReceiverBridge.saved.plist"];
}
- (void)setBusy:(BOOL)busy {
    self.activate.enabled=!busy;self.deactivate.enabled=!busy;self.restore.enabled=!busy;
}
- (NSError *)archiveLegacyAgent {
    NSFileManager *files=NSFileManager.defaultManager;NSError *error=nil;
    if(![files fileExistsAtPath:self.legacyPlist])return nil;
    [files createDirectoryAtPath:self.backupPlist.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error];
    if(error)return error;
    if([files fileExistsAtPath:self.backupPlist]){
        NSString *previous=[self.backupPlist stringByAppendingFormat:@".previous-%@",NSUUID.UUID.UUIDString];
        [files moveItemAtPath:self.backupPlist toPath:previous error:&error];
        if(error)return error;
    }
    [files moveItemAtPath:self.legacyPlist toPath:self.backupPlist error:&error];
    return error;
}
- (void)activateDriver:(id)sender {
    (void)sender;
    if(![NSBundle.mainBundle.bundlePath hasPrefix:@"/Applications/"]){
        self.status.stringValue=@"Copy macBitdo Driver.app to /Applications first, then open that copy and activate the driver.";return;
    }
    [self launchctl:@[@"bootout",[NSString stringWithFormat:@"gui/%u/%@",getuid(),legacyLabel]]];
    for(NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.zbreilly.ReceiverBridge"])
        [app terminate];
    NSError *archiveError=[self archiveLegacyAgent];
    if(archiveError){
        self.status.stringValue=[NSString stringWithFormat:@"Could not disable the previous bridge's login startup: %@. Driver activation was not requested. Restore Old Bridge is available.",archiveError.localizedDescription];return;
    }
    self.removing=NO;self.restoreAfterRemoval=NO;
    [self setBusy:YES];self.status.stringValue=@"Requesting DriverKit activation. If macOS asks, approve macBitdo Driver in System Settings. Keep this app open until activation finishes.";
    OSSystemExtensionRequest *request=[OSSystemExtensionRequest activationRequestForExtension:driverID queue:dispatch_get_main_queue()];
    request.delegate=self;[OSSystemExtensionManager.sharedManager submitRequest:request];
}
- (void)removeDriver:(id)sender {
    (void)sender;self.removing=YES;self.restoreAfterRemoval=NO;
    [self setBusy:YES];self.status.stringValue=@"Requesting removal of the DriverKit extension.";
    OSSystemExtensionRequest *request=[OSSystemExtensionRequest deactivationRequestForExtension:driverID queue:dispatch_get_main_queue()];
    request.delegate=self;[OSSystemExtensionManager.sharedManager submitRequest:request];
}
- (void)restoreBridge:(id)sender {
    (void)sender;
    self.removing=YES;self.restoreAfterRemoval=YES;[self setBusy:YES];
    self.status.stringValue=@"Removing the DriverKit extension before restoring the old bridge to prevent a USB conflict.";
    OSSystemExtensionRequest *request=[OSSystemExtensionRequest deactivationRequestForExtension:driverID queue:dispatch_get_main_queue()];
    request.delegate=self;[OSSystemExtensionManager.sharedManager submitRequest:request];
}
- (void)finishRestore {
    [self setBusy:NO];
    NSFileManager *files=NSFileManager.defaultManager;NSError *error=nil;
    if(![files fileExistsAtPath:self.legacyPlist]&&[files fileExistsAtPath:self.backupPlist]){
        [files createDirectoryAtPath:self.legacyPlist.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error];
        if(!error)[files moveItemAtPath:self.backupPlist toPath:self.legacyPlist error:&error];
    }
    if(error||![files fileExistsAtPath:self.legacyPlist]){
        self.status.stringValue=error.localizedDescription?:@"No previous bridge login agent was found.";return;
    }
    int result=[self launchctl:@[@"bootstrap",[NSString stringWithFormat:@"gui/%u",getuid()],self.legacyPlist]];
    self.status.stringValue=result==0?@"Previous bridge restored. Remove the DriverKit driver before using it, so only one controller implementation owns USB.":@"Could not restore the previous bridge. Check the saved agent and driver activation state.";
}
- (void)requestNeedsUserApproval:(OSSystemExtensionRequest *)request {
    (void)request;self.status.stringValue=@"macOS requires your approval. Open System Settings and allow macBitdo Driver under the driver/system-extension controls. Keep this app open until the request completes.";
}
- (OSSystemExtensionReplacementAction)request:(OSSystemExtensionRequest *)request
    actionForReplacingExtension:(OSSystemExtensionProperties *)existing
    withExtension:(OSSystemExtensionProperties *)replacement {
    (void)request;(void)existing;(void)replacement;return OSSystemExtensionReplacementActionReplace;
}
- (void)request:(OSSystemExtensionRequest *)request didFinishWithResult:(OSSystemExtensionRequestResult)result {
    [self setBusy:NO];
    if(result==OSSystemExtensionRequestWillCompleteAfterReboot){
        self.status.stringValue=@"macOS accepted the request and requires a restart to finish it.";return;
    }
    if(request==nil)return;
    if(self.removing){
        if(self.restoreAfterRemoval)[self finishRestore];
        else self.status.stringValue=@"Driver removed. The previous bridge remains stopped unless you choose to restore it.";
        return;
    }
    self.status.stringValue=@"Driver activated. You can close this app and open Moonlight normally. Reconnect the receiver if another prototype still held it during activation.";
}
- (void)request:(OSSystemExtensionRequest *)request didFailWithError:(NSError *)error {
    if(self.removing&&self.restoreAfterRemoval&&[error.domain isEqualToString:OSSystemExtensionErrorDomain]&&
        error.code==OSSystemExtensionErrorExtensionNotFound){[self finishRestore];return;}
    (void)request;[self setBusy:NO];
    if(!self.removing){
        // Activation stopped the old bridge first; put it back so a failed
        // activation does not leave the controller with no driver at all.
        [self finishRestore];
        self.status.stringValue=[NSString stringWithFormat:@"Activation failed: %@. %@",error.localizedDescription,self.status.stringValue];
        return;
    }
    self.status.stringValue=[NSString stringWithFormat:@"Removal failed: %@.",error.localizedDescription];
}
@end

int main(void) { @autoreleasepool {
    NSApplication *application=NSApplication.sharedApplication;
    static DriverApp *delegate;delegate=[DriverApp new];application.delegate=delegate;
    [application run];
    return 0;
}}
