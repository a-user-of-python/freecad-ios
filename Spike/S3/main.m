// Spike S3 (Phase A1) — minimal iOS embedding proof for the BeeWare
// Python 3.13 XCFramework.
//
// The app links Python.xcframework, Py_Initialize's with PYTHONHOME
// pointed at the in-bundle python/ tree (installed by the build
// script from the XCFramework, BeeWare's install_python layout), runs
// probe.py, and leaves the probe's report in the app container's
// Documents/s3-result.txt (visible in Files: the physical Info.plist
// carries UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace).
// The same full report is ALSO displayed on screen in a scrollable
// UITextView (20pt monospaced, white on black) — the primary channel
// since the 2026-10-29 fix. NSLog mirrors the same lines.
//
// This is a spike harness, not FreeCAD code: no patches, no Qt.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Python/Python.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) UITextView *resultView;
@property (strong, nonatomic) NSString *resultPath;
@end

@implementation AppDelegate

- (void)runProbe {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundlePath = [bundle bundlePath];
    NSString *pythonHome = [bundlePath stringByAppendingPathComponent:@"python"];
    NSString *probePath = [bundle pathForResource:@"probe" ofType:@"py"];

    NSArray *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *resultPath = [[docs firstObject]
        stringByAppendingPathComponent:@"s3-result.txt"];
    self.resultPath = resultPath;

    // Started-marker from the host side: if this file says STARTED but
    // the probe never overwrote it, the interpreter died mid-run.
    [@"S3-MAIN-STARTED\n" writeToFile:resultPath atomically:YES
                             encoding:NSUTF8StringEncoding error:nil];

    PyConfig config;
    PyConfig_InitPythonConfig(&config);
    config.write_bytecode = 0;
    config.buffered_stdio = 0;
    wchar_t *home = Py_DecodeLocale([pythonHome UTF8String], NULL);
    if (home != NULL) {
        PyStatus st = PyConfig_SetString(&config, &config.home, home);
        PyMem_RawFree(home);
        if (PyStatus_Exception(st)) {
            NSLog(@"S3: PyConfig_SetString(home) failed");
        }
    }
    PyStatus status = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) {
        NSString *msg = [NSString stringWithFormat:
            @"PYTHON-EMBED-FAIL Py_InitializeFromConfig: %s\n",
            status.err_msg ? status.err_msg : "(no message)"];
        NSLog(@"%@", msg);
        [msg writeToFile:resultPath atomically:YES
                encoding:NSUTF8StringEncoding error:nil];
        return;
    }

    // Hand the probe its result path through a Python global.
    NSString *prelude = [NSString stringWithFormat:
        @"S3_RESULT_PATH = %@\n",
        [NSString stringWithFormat:@"'%@'", resultPath]];
    PyRun_SimpleString([prelude UTF8String]);

    FILE *fp = fopen([probePath UTF8String], "r");
    if (fp == NULL) {
        NSLog(@"S3: probe.py missing from bundle");
        [@"PYTHON-EMBED-FAIL probe.py missing\n" writeToFile:resultPath
            atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    int rc = PyRun_SimpleFileExFlags(fp, "probe.py", 1, NULL);
    NSLog(@"S3: probe rc=%d", rc);
    Py_Finalize();
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor blackColor];
    // Self-reporting (2026-10-29 fix): the FULL probe result is shown
    // on screen in a scrollable text view — the primary channel now.
    // The Documents/s3-result.txt write in runProbe/probe.py stays as
    // the secondary channel (readable via Files now that the physical
    // Info.plist carries UIFileSharingEnabled).
    UITextView *tv = [[UITextView alloc] initWithFrame:vc.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                          UIViewAutoresizingFlexibleHeight;
    tv.backgroundColor = [UIColor blackColor];
    tv.textColor = [UIColor whiteColor];
    tv.font = [UIFont monospacedSystemFontOfSize:20.0
                                           weight:UIFontWeightRegular];
    tv.editable = NO;
    tv.selectable = YES;
    tv.scrollEnabled = YES;
    tv.alwaysBounceVertical = YES;
    tv.textContainerInset = UIEdgeInsetsMake(24, 16, 24, 16);
    tv.text = @"S3 Python spike\n\nRunning Python probe...";
    [vc.view addSubview:tv];
    self.resultView = tv;
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    [self runProbe];

    NSString *result = self.resultPath
        ? [NSString stringWithContentsOfFile:self.resultPath
                                    encoding:NSUTF8StringEncoding
                                       error:nil]
        : nil;
    if (result.length == 0) {
        result = @"PYTHON-EMBED-FAIL: probe finished but no result "
                  "text could be read back from Documents/s3-result.txt";
    }
    self.resultView.text = result;
    // CGPointMake, not CGPointZero: the harness links only
    // Python/Foundation/UIKit, and _CGPointZero lives in CoreGraphics.
    [self.resultView setContentOffset:CGPointMake(0, 0) animated:NO];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass([AppDelegate class]));
    }
}
