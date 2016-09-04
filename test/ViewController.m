//
//  ViewController.m
//  test
//
//  Created by brianliu on 2016/09/02.
//  Copyright © 2016年 winnerwave. All rights reserved.
//

#import "ViewController.h"
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOCFPlugIn.h>

#define err_get_system(err) (((err)>>26)&0x3f) 
#define err_get_sub(err) (((err)>>14)&0xfff) 
#define err_get_code(err) ((err)&0x3fff)
@import DiskArbitration;
void what(io_service_t media);
NSDictionary * attributes(io_service_t usbDevice);
static io_service_t findUSBDeviceForMedia(io_service_t
                                          media);
static bool getVidAndPid(io_service_t device, int
                         *vid, int *pid);

void showError(kern_return_t err){
    NSLog(@"system 0x%x, sub 0x%x, code 0x%x", err_get_system(err), err_get_sub(err), err_get_code(err));
}

NSURL* diskVolumePath(DADiskRef disk){
    CFDictionaryRef diskinfo = DADiskCopyDescription(disk);
    CFURLRef fspath = CFDictionaryGetValue(diskinfo, kDADiskDescriptionVolumePathKey);
    
    char buf[MAXPATHLEN];
    BOOL result = CFURLGetFileSystemRepresentation(fspath, true, (UInt8 *)buf, sizeof(buf));
    if (result) {
        //        printf("Disk %s mounted at %s\n",
        //               DADiskGetBSDName(disk),
        //               buf);
        
        /* Print the complete dictionary for debugging. */
        //        CFShow(diskinfo);
        return (__bridge NSURL*)fspath;
    } else {
        /* Something is *really* wrong. */
    }
    return nil;
}

void got_disk(DADiskRef disk, void *context)
{
    
//    NSLog(@"new disk: %@", attributes(DADiskCopyIOMedia(disk)));
//    what(DADiskCopyIOMedia(disk));
    
    io_service_t usb = findUSBDeviceForMedia(DADiskCopyIOMedia(disk));
    int pid = 0;
    int vid = 0;
    
    getVidAndPid(usb, &vid, &pid);
    NSLog(@"vid:%x, pid:%x", vid,pid);
}

void got_Volumed(DADiskRef disk, CFArrayRef keys, void *context)
{
    CFDictionaryRef dict = DADiskCopyDescription(disk);
    CFURLRef fspath = CFDictionaryGetValue(dict, kDADiskDescriptionVolumePathKey);
    
    char buf[MAXPATHLEN];
    if (CFURLGetFileSystemRepresentation(fspath, false, (UInt8 *)buf, sizeof(buf))) {
        printf("Disk %s is now at %s\nChanged keys:\n", DADiskGetBSDName(disk), buf);
        ;
        what(DADiskCopyIOMedia(disk));
  
        
    } else {
        /* Something is *really* wrong. */
    }
}
DADissenterRef allow_mount(
                           DADiskRef disk,
                           void *context)
{
    int allow = 1;
    
    if (allow) {
        /* Return NULL to allow */
        fprintf(stderr, "allow_mount: allowing mount.\n");
        return NULL;
    } else {
        /* Return a dissenter to deny */
        fprintf(stderr, "allow_mount: refusing mount.\n");
        return DADissenterCreate(
                                 kCFAllocatorDefault, kDAReturnExclusiveAccess,
                                 CFSTR("It's mine!"));
    }
}

void what(io_service_t media){
    kern_return_t kr = 0;
    NSMutableDictionary * dict = [NSMutableDictionary new];
    CFMutableDictionaryRef dictRef = (__bridge CFMutableDictionaryRef)(dict);
    kr = IORegistryEntryCreateCFProperties(media, &dictRef, kCFAllocatorDefault, 0);
    if(kr == KERN_SUCCESS){
        NSLog(@"dict:%@", dict);
    }
}



NSDictionary * attributes(io_service_t usbDevice){
    
    mach_port_t masterPort;
    

    kern_return_t kr;
    
    
    
    //Create a master port for communication with the I/O Kit
    
    kr = IOMasterPort (MACH_PORT_NULL, &masterPort);
    
    if (kr || !masterPort)
        
    {
        
        NSLog (@"Error: Couldn't create a master I/O Kit port(%08x)", kr);
        
        return NULL;
        
    }
    
    
    IOCFPlugInInterface**plugInInterface = NULL;
    
    SInt32 theScore;
    
    
    
    //Create an intermediate plug-in
    
    kr = IOCreatePlugInInterfaceForService(usbDevice, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &theScore);
    
    
    
    if ((kIOReturnSuccess != kr) || !plugInInterface) {
        
        printf("Unable to create a plug-in (%08x)\n", kr);
        showError(kr);
        return NULL;
    }
    
    IOUSBDeviceInterface182 **dev = NULL;
    
    
    
    //Create the device interface
    
    HRESULT result = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID)&dev);
    
    
    
    if (result || !dev)
    {
        printf("Couldn't create a device interface (%08x)\n", (int) result);
        return NULL;
    }
    
    
    UInt16 vendorId;
    
    UInt16 productId;
    
    UInt16 releaseId;
    
    
    
    //Get configuration Ids of the device
    
    (*dev)->GetDeviceVendor(dev, &vendorId);
    
    (*dev)->GetDeviceProduct(dev, &productId);
    
    (*dev)->GetDeviceReleaseNumber(dev, &releaseId);
    
    
    
    
    
    UInt8 stringIndex;
    
    
    
    (*dev)->USBGetProductStringIndex(dev, &stringIndex);
    
    
    
    IOUSBConfigurationDescriptorPtr descriptor;
    
    
    
    (*dev)->GetConfigurationDescriptorPtr(dev, stringIndex, &descriptor);
    
    
    
    //Get Device name
    
    io_name_t deviceName;
    
    kr = IORegistryEntryGetName (usbDevice, deviceName);
    
    if (kr != KERN_SUCCESS)
        
    {
        
        NSLog (@"fail 0x%8x", kr);
        
        deviceName[0] = '\0';
        
    }
    
    
    
    NSString * name = [NSString stringWithCString:deviceName encoding:NSASCIIStringEncoding];
    
    
    
    //data will be initialized only for USB storage devices.
    
    //bsdName can be converted to mounted path of the device and vice-versa using DiskArbitration framework, hence we can identify the device through it's mounted path
    
    CFTypeRef data = IORegistryEntrySearchCFProperty(usbDevice, kIOServicePlane, CFSTR("BSD Name"), kCFAllocatorDefault, kIORegistryIterateRecursively);
    
    NSString* bsdName = [(__bridge NSString*)data substringToIndex:5];
    
    
    
    NSString* attributeString = @"";
    NSMutableDictionary * dict = [NSMutableDictionary new];
    
    
    if(bsdName){
        
        attributeString = [NSString stringWithFormat:@"%@,%@,0x%x,0x%x,0x%x", name, bsdName, vendorId, productId, releaseId];
        
        dict[@"name"] = name;
        dict[@"bsdName"] = bsdName;
        dict[@"vendorId"] = [NSString stringWithFormat:@"0x%x", vendorId];
        dict[@"productId"] = [NSString stringWithFormat:@"0x%x", productId];
        dict[@"releaseId"] = [NSString stringWithFormat:@"0x%x", releaseId];
    }
    else{
        attributeString = [NSString stringWithFormat:@"%@,0x%x,0x%x,0x%x", name, vendorId, productId, releaseId];
        
        
        dict[@"name"] = name;
        dict[@"vendorId"] = [NSString stringWithFormat:@"0x%x", vendorId];
        dict[@"productId"] = [NSString stringWithFormat:@"0x%x", productId];
        dict[@"releaseId"] = [NSString stringWithFormat:@"0x%x", releaseId];
    }
    
    
    
    IOObjectRelease(usbDevice);
    
    (*plugInInterface)->Release(plugInInterface);
    
    (*dev)->Release(dev);

    //Finished with master port
    
    mach_port_deallocate(mach_task_self(), masterPort);
    
    masterPort = 0;
    
    return dict;
}


//Once you get the io_service_t from DADiskCopyIOMedia,
//you can call this function to get the IOUSBDevice
//object:
static io_service_t findUSBDeviceForMedia(io_service_t
                                          media)
{
    IOReturn status = kIOReturnSuccess;
    
    io_iterator_t		iterator = 0;
    io_service_t 		retService = 0;
    
    if (media == 0)
        return retService;
    
    status = IORegistryEntryCreateIterator(media,
                                           kIOServicePlane, (kIORegistryIterateParents |
                                                             kIORegistryIterateRecursively), &iterator);
    if (iterator == 0) {
        status = kIOReturnError;
    }
    
    if (status == kIOReturnSuccess)
    {
        io_service_t service = IOIteratorNext(iterator);
        while (service)
        {
            io_name_t serviceName;
            kern_return_t kr =
            IORegistryEntryGetNameInPlane(service,
                                          kIOServicePlane, serviceName);
            if ((kr == 0) && (IOObjectConformsTo(service,
                                                 "IOUSBDevice"))) {
                retService = service;
                break;
            }
            service = IOIteratorNext(iterator);
        }
    }
    return retService;
}
//http://lists.apple.com/archives/usb/2007/Nov/msg00038.html
//Once you get the IOUSBDevice object, you get the
//vendor ID and product ID by calling this function:

static bool getVidAndPid(io_service_t device, int
                         *vid, int *pid)
{
    bool success = false;
    
    CFNumberRef	cfVendorId =
    (CFNumberRef)IORegistryEntryCreateCFProperty(device,
                                                 CFSTR("idVendor"), kCFAllocatorDefault, 0);
    if (cfVendorId && (CFGetTypeID(cfVendorId) ==
                       CFNumberGetTypeID()))
    {
        Boolean result;
        result = CFNumberGetValue(cfVendorId,
                                  kCFNumberSInt32Type, vid);
        CFRelease(cfVendorId);
        if (result)
        {
            CFNumberRef	cfProductId =
            (CFNumberRef)IORegistryEntryCreateCFProperty(device,
                                                         CFSTR("idProduct"), kCFAllocatorDefault, 0);
            if (cfProductId && (CFGetTypeID(cfProductId) ==
                                CFNumberGetTypeID()))
            {
                Boolean result;
                result = CFNumberGetValue(cfProductId,
                                          kCFNumberSInt32Type, pid);
                CFRelease(cfProductId);
                if (result)
                {
                    success = true;
                }
            }
        }
    }
    
    return (success);
}


@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Notification for Mountingthe USB device
//    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(deviceMounted:) name:NSWorkspaceDidMountNotification object:nil];

    
//    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(deviceUnmounted:) name:NSWorkspaceDidUnmountNotification object:nil];

    [self s];
}



-(void)s{
   
    _session = DASessionCreate(kCFAllocatorDefault);
//    void *context = NULL;
    
    DARegisterDiskAppearedCallback(_session, kDADiskDescriptionMatchVolumeMountable, got_disk, NULL);
    
    
    CFMutableArrayRef keys = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
    CFArrayAppendValue(keys, kDADiskDescriptionVolumePathKey);
    DARegisterDiskDescriptionChangedCallback(_session,
                                             NULL, /* match all disks */
                                             keys, /* match the keys specified above */
                                             got_Volumed,
                                             NULL);
    
    DARegisterDiskMountApprovalCallback(_session,
                                        NULL, /* Match all disks */
                                        allow_mount,
                                        NULL); /* No context */
    
    
    DASessionSetDispatchQueue(_session, dispatch_get_main_queue());
    
    
    
}

- (IBAction)flickr:(id)sender {
    [self deviceMounted:nil];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    
    // Update the view, if already loaded.
}

-(void)deviceMounted:(NSNotification*)notification{
    NSArray* devices = [[NSFileManager defaultManager] mountedVolumeURLsIncludingResourceValuesForKeys:nil options:0];
    
        for (NSURL* url in devices) {
            if(url != nil){
    //            NSLog(@"%@",dict);
                NSLog(@"path(%@):%@",url,[self sdf:url]);
            }
            
        }
    
//    NSArray * attributes = [self deviceAttributes];
//    
////    NSLog(@"devices:%@", devices);
//    
////    NSLog(@"attributes:%@", attributes);
//    
//    for (NSDictionary* dict in attributes) {
//        NSString * bsdName = [dict objectForKey:@"bsdName"];
//        if(bsdName != nil){
////            NSLog(@"%@",dict);
//            NSLog(@"path(%@):%@",bsdName,[self sdf:bsdName]);
//        }
//        
//    }
//    
    
}

-(void)deviceUnmounted:(NSNotification*)notification{
    
}
// The following code will return an array having configured Ids and Name of all the mounted USB devices.



-(NSArray <NSDictionary*> *) deviceAttributes

{
    
    mach_port_t masterPort;
    
    CFMutableDictionaryRef matchingDict;
    
    
    
    NSMutableArray * devicesAttributes = [NSMutableArray array];
    
    
    
    kern_return_t kr;
    
    
    
    //Create a master port for communication with the I/O Kit
    
    kr = IOMasterPort (MACH_PORT_NULL, &masterPort);
    
    if (kr || !masterPort)
        
    {
        
        NSLog (@"Error: Couldn't create a master I/O Kit port(%08x)", kr);
        
        return devicesAttributes;
        
    }
    
    
    
    //Set up matching dictionary for class IOUSBDevice and its subclasses
    
    matchingDict = IOServiceMatching (kIOUSBDeviceClassName);
    
    if (!matchingDict)
        
    {
        
        NSLog (@"Error: Couldn't create a USB matching dictionary");
        
        mach_port_deallocate(mach_task_self(), masterPort);
        
        return devicesAttributes;
        
    }
    
    
    
    io_iterator_t iterator;
    
    IOServiceGetMatchingServices (kIOMasterPortDefault, matchingDict, &iterator);
    
    
    
    io_service_t usbDevice;
    
    
    
    //Iterate for USB devices
    
    while ((usbDevice = IOIteratorNext (iterator)))
        
    {
        
        IOCFPlugInInterface**plugInInterface = NULL;
        
        SInt32 theScore;
        
        
        
        //Create an intermediate plug-in
        
        kr = IOCreatePlugInInterfaceForService(usbDevice, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &theScore);
        
        
        
        if ((kIOReturnSuccess != kr) || !plugInInterface)
            
            printf("Unable to create a plug-in (%08x)\n", kr);
        
        
        
        IOUSBDeviceInterface182 **dev = NULL;
        
        
        
        //Create the device interface
        
        HRESULT result = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID)&dev);
        
        
        
        if (result || !dev)
            
            printf("Couldn't create a device interface (%08x)\n", (int) result);
        
        
        
        UInt16 vendorId;
        
        UInt16 productId;
        
        UInt16 releaseId;
        
        
        
        //Get configuration Ids of the device
        
        (*dev)->GetDeviceVendor(dev, &vendorId);
        
        (*dev)->GetDeviceProduct(dev, &productId);
        
        (*dev)->GetDeviceReleaseNumber(dev, &releaseId);
        
        
        
        
        
        UInt8 stringIndex;
        
        
        
        (*dev)->USBGetProductStringIndex(dev, &stringIndex);
        
        
        
        IOUSBConfigurationDescriptorPtr descriptor;
        
        
        
        (*dev)->GetConfigurationDescriptorPtr(dev, stringIndex, &descriptor);
        
        
        
        //Get Device name
        
        io_name_t deviceName;
        
        kr = IORegistryEntryGetName (usbDevice, deviceName);
        
        if (kr != KERN_SUCCESS)
            
        {
            
            NSLog (@"fail 0x%8x", kr);
            
            deviceName[0] = '\0';
            
        }
        
        
        
        NSString * name = [NSString stringWithCString:deviceName encoding:NSASCIIStringEncoding];
        
        
        
        //data will be initialized only for USB storage devices.
        
        //bsdName can be converted to mounted path of the device and vice-versa using DiskArbitration framework, hence we can identify the device through it's mounted path
        
        CFTypeRef data = IORegistryEntrySearchCFProperty(usbDevice, kIOServicePlane, CFSTR("BSD Name"), kCFAllocatorDefault, kIORegistryIterateRecursively);
        
        NSString* bsdName = [(__bridge NSString*)data substringToIndex:5];
        
        
        
        NSString* attributeString = @"";
        NSMutableDictionary * dict = [NSMutableDictionary new];
        
        
        if(bsdName){
            
            attributeString = [NSString stringWithFormat:@"%@,%@,0x%x,0x%x,0x%x", name, bsdName, vendorId, productId, releaseId];
            
            dict[@"name"] = name;
            dict[@"bsdName"] = bsdName;
            dict[@"vendorId"] = [NSString stringWithFormat:@"0x%x", vendorId];
            dict[@"productId"] = [NSString stringWithFormat:@"0x%x", productId];
            dict[@"releaseId"] = [NSString stringWithFormat:@"0x%x", releaseId];
        }
        else{
            attributeString = [NSString stringWithFormat:@"%@,0x%x,0x%x,0x%x", name, vendorId, productId, releaseId];
            
            
            dict[@"name"] = name;
            dict[@"vendorId"] = [NSString stringWithFormat:@"0x%x", vendorId];
            dict[@"productId"] = [NSString stringWithFormat:@"0x%x", productId];
            dict[@"releaseId"] = [NSString stringWithFormat:@"0x%x", releaseId];
        }
        
        [devicesAttributes addObject:dict];
        

        IOObjectRelease(usbDevice);
        
        (*plugInInterface)->Release(plugInInterface);
        
        (*dev)->Release(dev);
        
    }
    
    
    
    //Finished with master port
    
    mach_port_deallocate(mach_task_self(), masterPort);
    
    masterPort = 0;
    
    return devicesAttributes;
    
}


-(NSString*)sdf:(NSURL*)url{
    if (url == nil){
        return nil;
    }
    
    
    DASessionRef session;
    session = DASessionCreate(kCFAllocatorDefault);

    
    DADiskRef disk;
    CFURLRef cfurl = (__bridge CFURLRef)url;
    disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, cfurl);
//    disk  = DADiskCreateFromBSDName(kCFAllocatorDefault, session, [bsdName UTF8String]);
    
    CFDictionaryRef diskinfo;
    diskinfo = DADiskCopyDescription(disk);
    CFURLRef fspath = CFDictionaryGetValue(diskinfo, kDADiskDescriptionVolumePathKey);
    
    char buf[MAXPATHLEN];
    if (CFURLGetFileSystemRepresentation(fspath, false, (UInt8 *)buf, sizeof(buf))) {
        printf("Disk %s mounted at %s\n",
               DADiskGetBSDName(disk),buf);
//        CFShow(diskinfo);
        return  [NSString stringWithUTF8String:buf];
        
        /* Print the complete dictionary for debugging. */
        
    } else {
        /* Something is *really* wrong. */
    }
    
    return nil;
}


@end
