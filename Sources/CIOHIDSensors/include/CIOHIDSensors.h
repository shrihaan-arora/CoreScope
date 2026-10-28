/*
 * CIOHIDSensors — Private IOHIDEventSystem API Declarations
 *
 * These are opaque CoreFoundation types from the private IOKit HID event
 * subsystem. They are NOT part of any public Apple SDK header. Apple
 * Silicon exposes PMU temperature sensors as IOHIDServices that can be
 * queried without root or a privileged helper.
 *
 * The functions declared here are resolved at runtime by the linker from
 * /System/Library/Frameworks/IOKit.framework. This module does NOT ship
 * any compiled C code; it exists solely to provide type/function
 * declarations that Swift can consume.
 *
 * DO NOT use these APIs to *write* to sensors or modify hardware state.
 * Read-only, on-demand temperature collection is the only intended use.
 */

#ifndef CIOHIDSENSORS_H
#define CIOHIDSENSORS_H

#include <CoreFoundation/CoreFoundation.h>

/* Opaque handle types */
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient      *IOHIDServiceClientRef;
typedef struct __IOHIDEvent              *IOHIDEventRef;

/* Create a client handle for the HID event system.
   Returns a +1 CF reference that must be CFRelease'd. */
IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);

/* Restrict the client to services matching the given dictionary.
   For temperature sensors: PrimaryUsagePage=0xFF00, PrimaryUsage=5. */
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client,
                                      CFDictionaryRef            matching);

/* Copy the array of matching IOHIDServiceClientRef objects.
   Returns a +1 CFArrayRef that must be CFRelease'd. */
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);

/* Copy a named CF property from a service.
   "Product" returns the sensor name (e.g. "PMU tdie1").
   Returns a +1 CFTypeRef that must be CFRelease'd, or NULL. */
CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service,
                                         CFStringRef            key);

/* Copy the most recent event of the specified type from a service.
   type=15 (kIOHIDEventTypeTemperature). options and timestamp are
   ordinarily zero. Returns a +1 IOHIDEventRef, or NULL. */
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service,
                                          int64_t               type,
                                          int32_t               options,
                                          int64_t               timestamp);

/* Extract a floating-point field from an event.
   For temperature events the field selector is (15 << 16).
   Returns the value in degrees Celsius. */
double IOHIDEventGetFloatValue(IOHIDEventRef event,
                               int64_t       field);

/* Helper functions: release opaque IOKit pointers.
   Swift imports these typedefs as OpaquePointer. These helpers safely
   call CFRelease from C. */
void CIOHIDEventSystemClientRelease(IOHIDEventSystemClientRef client);
void CIOHIDEventRelease(IOHIDEventRef event);
void CIOHIDRelease(const void *ref);

#endif /* CIOHIDSENSORS_H */
