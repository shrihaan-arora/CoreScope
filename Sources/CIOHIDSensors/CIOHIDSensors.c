/*
 * CIOHIDSensors — implementation file.
 *
 * Provides C-side release helpers for opaque CoreFoundation/IOKit pointers
 * so Swift code can safely release handles without pointer cast issues.
 */

#include "CIOHIDSensors.h"

void CIOHIDEventSystemClientRelease(IOHIDEventSystemClientRef client) {
    if (client) {
        CFRelease((CFTypeRef)client);
    }
}

void CIOHIDEventRelease(IOHIDEventRef event) {
    if (event) {
        CFRelease((CFTypeRef)event);
    }
}

void CIOHIDRelease(const void *ref) {
    if (ref) {
        CFRelease((CFTypeRef)ref);
    }
}
