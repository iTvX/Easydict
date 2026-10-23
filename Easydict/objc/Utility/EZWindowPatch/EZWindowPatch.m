//
//  EZWindowPatch.m
//  Easydict
//
//  Created by asdmoment on 2026/4/26.
//  Copyright © 2026 izual. All rights reserved.
//

#import "EZWindowPatch.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

/// How to search one loaded image for NSWindow subclasses that override `_cornerMask`.
typedef NS_ENUM(NSInteger, EZCornerMaskImageScan) {
    EZCornerMaskImageScanNone,
    /// Large UI frameworks: only check classes whose names look like windows.
    EZCornerMaskImageScanWindowNames,
    /// Small frameworks: check every class, since `IKPictureTaker` has no window-like name.
    EZCornerMaskImageScanAllClasses,
};

/// Picks the scan for an image. Only these frameworks ship overriding classes:
/// AppKit (`_NSTextFinderOverlayWindow`), SwiftUI (`SwiftUISuggestionsWindow`),
/// QuickLookUI (`QLPreviewPanel`, `QLBubbleWindow`) and ImageKit (`IKPictureTaker`).
/// Scanning every loaded image with `objc_copyClassList` finds no others, but it realizes
/// every class in the process, which costs about 12 MB resident and 10 ms at launch.
static EZCornerMaskImageScan EZCornerMaskScanForImage(const char *imagePath) {
    const char *slash = strrchr(imagePath, '/');
    const char *imageName = slash ? slash + 1 : imagePath;
    if (strcmp(imageName, "AppKit") == 0 || strcmp(imageName, "SwiftUI") == 0 || strcmp(imageName, "SwiftUICore") == 0) {
        return EZCornerMaskImageScanWindowNames;
    }
    if (strcmp(imageName, "QuickLookUI") == 0 || strcmp(imageName, "ImageKit") == 0) {
        return EZCornerMaskImageScanAllClasses;
    }
    return EZCornerMaskImageScanNone;
}

/// Whether a class name looks like a window class. Reading names does not realize classes,
/// so filtering by name first keeps realization limited to a few hundred window classes.
static BOOL EZClassNameLooksLikeWindow(const char *className) {
    return strstr(className, "Window") != NULL || strstr(className, "Panel") != NULL;
}

void EZPatchWindowServerCornerMask(void) {
    // Register the private selector by name only. We do not call it here;
    // the patch only compares and rewrites Objective-C method entries.
    SEL sel = sel_registerName("_cornerMask");
    Class nsWindowClass = [NSWindow class];

    // Use NSWindow's IMP as a deterministic baseline. Classes are visited in
    // unspecified order, so taking the IMP from each class's immediate
    // superclass would let a child patched before its parent inherit the
    // parent's still-custom IMP and keep bypassing AppKit's shared cache path.
    Method baselineMethod = class_getInstanceMethod(nsWindowClass, sel);
    if (!baselineMethod) return;
    IMP baselineIMP = method_getImplementation(baselineMethod);
    if (!baselineIMP) return;

    // This returns a snapshot of images already loaded in this process.
    // Classes loaded later by a framework or bundle are not included here.
    unsigned int imageCount = 0;
    const char **imagePaths = objc_copyImageNames(&imageCount);
    if (!imagePaths) return;

    for (unsigned int imageIndex = 0; imageIndex < imageCount; imageIndex++) {
        const char *imagePath = imagePaths[imageIndex];
        EZCornerMaskImageScan scan = EZCornerMaskScanForImage(imagePath);
        if (scan == EZCornerMaskImageScanNone) continue;

        unsigned int classCount = 0;
        const char **classNames = objc_copyClassNamesForImage(imagePath, &classCount);
        if (!classNames) continue;

        for (unsigned int i = 0; i < classCount; i++) {
            const char *className = classNames[i];
            if (scan == EZCornerMaskImageScanWindowNames && !EZClassNameLooksLikeWindow(className)) continue;

            Class cls = objc_getClass(className);
            if (!cls || cls == nsWindowClass) continue;

            // Walk the superclass chain manually so private AppKit, SwiftUI,
            // QuickLook, and ImageKit window subclasses are covered too.
            BOOL isWindowSubclass = NO;
            Class ancestor = class_getSuperclass(cls);
            while (ancestor) {
                if (ancestor == nsWindowClass) {
                    isWindowSubclass = YES;
                    break;
                }
                ancestor = class_getSuperclass(ancestor);
            }
            if (!isWindowSubclass) continue;

            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);
            if (!methods) continue;

            // class_copyMethodList only returns methods declared on cls itself.
            // That lets us distinguish a direct override from an inherited method.
            BOOL hasDirectOverride = NO;
            for (unsigned int j = 0; j < methodCount; j++) {
                // Selectors are uniqued by the Objective-C runtime, so pointer
                // equality is the correct comparison here.
                if (method_getName(methods[j]) == sel) {
                    hasDirectOverride = YES;
                    break;
                }
            }
            free(methods);
            if (!hasDirectOverride) continue;

            Method method = class_getInstanceMethod(cls, sel);
            if (!method) continue;

            // Replacing the IMP changes dispatch for all instances of this class,
            // including windows created after this startup patch runs.
            method_setImplementation(method, baselineIMP);
            NSLog(@"[WindowServer patch] Patched %s._cornerMask", className);
        }

        free(classNames);
    }

    free(imagePaths);
}
