// Spike S3 Phase A2 — iOS harness main (ObjC++).
//
// Strategy (front 03 Phase A, synthesis §3 S3):
//   1. Pre-initialise the BeeWare Python 3.13 interpreter EXACTLY as
//      the A1 harness does (PyConfig home = in-bundle python/ tree).
//      FreeCAD's InterpreterSingleton::init() skips its own init when
//      Py_IsInitialized() is already true, so the A1-proven stdlib
//      layout is preserved instead of FreeCAD's isolated-config path
//      (which would go hunting for a desktop-style Python install).
//   2. App::Application::init() with a synthetic argv carrying
//      -M <bundle>/Mod and -P <bundle>/lib so FreeCAD's own module
//      machinery finds the packaged console stack (model 1: in-bundle
//      dlopen of the C++ extension modules).
//   3. Run probe_a2_prelude.py (path/Init.py belt-and-braces), then
//      probe_a2.py, through Base::Interpreter().runFile().
//   4. The probe writes Documents/s3-a2-result.txt; the CI script
//      retrieves it from the simulator app container (simctl), the
//      same evidence route as A1. All evidence is SIMULATOR evidence.
//
// This file is spike code, not FreeCAD code.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <Python/Python.h>

#include <App/Application.h>
#include <Base/Exception.h>
#include <Base/Interpreter.h>

#include <cstdio>
#include <cstdlib>
#include <string>

@interface A2Delegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

static std::string gDocsPath;
static std::string gBundlePath;

static void writeHarnessNote(const std::string &text) {
    // Append to the result file ONLY if the probe hasn't created it;
    // harness-level failures land here so CI can see them.
    std::string path = gDocsPath + "/s3-a2-result.txt";
    FILE *fp = fopen(path.c_str(), "a");
    if (fp) {
        fputs(text.c_str(), fp);
        fputc('\n', fp);
        fclose(fp);
    }
    NSLog(@"A2: %s", text.c_str());
}

static void runA2() {
    NSString *bundle = [NSBundle mainBundle].bundlePath;
    gBundlePath = std::string([bundle UTF8String]);
    NSArray *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES);
    gDocsPath = std::string([[docs firstObject] UTF8String]);

    std::string pythonHome = gBundlePath + "/python";
    std::string resultPath = gDocsPath + "/s3-a2-result.txt";
    std::string preludePath = gBundlePath + "/probe_a2_prelude.py";
    std::string probePath = gBundlePath + "/probe_a2.py";
    std::string userHome = gDocsPath + "/FreeCADUser";

    // Started-marker: if this survives, the harness died mid-run.
    {
        FILE *fp = fopen(resultPath.c_str(), "w");
        if (fp) { fputs("A2-MAIN-STARTED\n", fp); fclose(fp); }
    }

    setenv("PYTHONHOME", pythonHome.c_str(), 1);
    setenv("FREECAD_USER_HOME", userHome.c_str(), 1);
    setenv("S3_BUNDLE", gBundlePath.c_str(), 1);
    setenv("S3_DOCS", gDocsPath.c_str(), 1);

    // --- Step 1: pre-initialise Python (A1-proven BeeWare layout) ---
    PyConfig config;
    PyConfig_InitPythonConfig(&config);
    config.write_bytecode = 0;
    config.buffered_stdio = 0;
    {
        wchar_t *home = Py_DecodeLocale(pythonHome.c_str(), nullptr);
        if (home) {
            PyStatus st = PyConfig_SetString(&config, &config.home, home);
            PyMem_RawFree(home);
            if (PyStatus_Exception(st)) {
                writeHarnessNote("A2-HARNESS-FAIL PyConfig_SetString(home)");
                return;
            }
        }
    }
    std::string exePath = gBundlePath + "/S3A2";
    {
        char *argv0 = const_cast<char *>(exePath.c_str());
        char *argvArr[1] = {argv0};
        PyStatus st = PyConfig_SetBytesArgv(&config, 1, argvArr);
        if (PyStatus_Exception(st)) {
            writeHarnessNote("A2-HARNESS-FAIL PyConfig_SetBytesArgv");
            return;
        }
    }
    PyStatus status = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) {
        writeHarnessNote(std::string("A2-HARNESS-FAIL Py_InitializeFromConfig: ") +
                         (status.err_msg ? status.err_msg : "(no message)"));
        return;
    }
    writeHarnessNote("A2-PYTHON-PREINIT-OK");

    // --- Step 2: FreeCAD application init ----------------------------
    App::Application::Config()["ExeName"] = "FreeCAD";
    App::Application::Config()["ExeVendor"] = "FreeCAD";
    App::Application::Config()["AppDataSkipVendor"] = "true";
    App::Application::Config()["RunMode"] = "Exit";
    App::Application::Config()["LoggingConsole"] = "1";

    std::string modPath = gBundlePath + "/Mod";
    std::string libPath = gBundlePath + "/lib";
    char arg0[1024], argM[16], argMod[2048], argP[16], argLib[2048];
    snprintf(arg0, sizeof(arg0), "%s", exePath.c_str());
    snprintf(argM, sizeof(argM), "-M");
    snprintf(argMod, sizeof(argMod), "%s", modPath.c_str());
    snprintf(argP, sizeof(argP), "-P");
    snprintf(argLib, sizeof(argLib), "%s", libPath.c_str());
    char *fargv[6] = {arg0, argM, argMod, argP, argLib, nullptr};
    int fargc = 5;

    try {
        App::Application::init(fargc, fargv);
    } catch (const Base::Exception &e) {
        writeHarnessNote(std::string("A2-HARNESS-FAIL Application::init: ") + e.what());
        return;
    } catch (const std::exception &e) {
        writeHarnessNote(std::string("A2-HARNESS-FAIL Application::init (std): ") + e.what());
        return;
    } catch (...) {
        writeHarnessNote("A2-HARNESS-FAIL Application::init (unknown)");
        return;
    }
    writeHarnessNote("A2-FREECAD-INIT-OK");

    // --- Step 3: prelude + probe --------------------------------------
    try {
        std::string prelude = "S3_RESULT_PATH = '" + resultPath + "'\n";
        Base::Interpreter().runString(prelude.c_str());
        Base::Interpreter().runFile(preludePath.c_str(), true);
        writeHarnessNote("A2-PRELUDE-DONE");
        Base::Interpreter().runFile(probePath.c_str(), true);
    } catch (const Base::Exception &e) {
        writeHarnessNote(std::string("A2-HARNESS-FAIL runFile: ") + e.what());
        return;
    } catch (const std::exception &e) {
        writeHarnessNote(std::string("A2-HARNESS-FAIL runFile (std): ") + e.what());
        return;
    } catch (...) {
        writeHarnessNote("A2-HARNESS-FAIL runFile (unknown)");
        return;
    }
    writeHarnessNote("A2-HARNESS-DONE");
}

@implementation A2Delegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor blackColor];
    UILabel *label = [[UILabel alloc] initWithFrame:vc.view.bounds];
    label.text = @"S3 A2 FreeCAD spike\n(see Documents/s3-a2-result.txt)";
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:24];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    [vc.view addSubview:label];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    // Run after launch completes so the simulator's launch watchdog
    // is not held by FreeCAD's init; CI polls for the result file.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        runA2();
    });
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass([A2Delegate class]));
    }
}
