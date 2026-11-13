#!/usr/bin/env python3
"""Generate the checked-in two-target Xcode project with no third-party tools."""
from pathlib import Path
import hashlib,json,plistlib
root=Path(__file__).resolve().parent
objects={}
def ident(name):return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(token,isa,**values):
    key=ident(token);objects[key]={'isa':isa,**values};return key
def file(name,path,kind):return add(name,'PBXFileReference',lastKnownFileType=kind,path=path,sourceTree='<group>')
def sources(name,refs):
    entries=[add(name+str(i),'PBXBuildFile',fileRef=ref) for i,ref in enumerate(refs)]
    return add(name,'PBXSourcesBuildPhase',buildActionMask=2147483647,files=entries,runOnlyForDeploymentPostprocessing=0)
def configs(name,settings):
    cs=[]
    for mode in ('Debug','Release'):
        cs.append(add(name+mode,'XCBuildConfiguration',name=mode,buildSettings={**settings,'GCC_OPTIMIZATION_LEVEL':'0' if mode=='Debug' else 's'}))
    return add(name+'configs','XCConfigurationList',buildConfigurations=cs,defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
cpp=file('devicecpp','Driver/UltimateReceiverDevice.cpp','sourcecode.cpp.cpp')
iig=file('deviceiig','Driver/UltimateReceiverDevice.iig','sourcecode.iig')
hidcpp=file('hidcpp','Driver/UltimateReceiverHID.cpp','sourcecode.cpp.cpp')
hidiig=file('hidiig','Driver/UltimateReceiverHID.iig','sourcecode.iig')
protocol=file('protocol','Driver/ReceiverProtocol.h','sourcecode.c.h')
hostmain=file('hostmain','Host/main.m','sourcecode.c.objc')
for name,path in [('driverplist','Driver/Info.plist'),('driverent','Driver/Driver.entitlements'),('hostplist','Host/Info.plist'),('hostent','Host/Host.entitlements')]:
    file(name,path,'text.plist.xml')
driverproduct=add('driverproduct','PBXFileReference',explicitFileType='wrapper.driver-extension',path='com.zbreilly.macBitdo.DriverHost.Receiver.dext',sourceTree='BUILT_PRODUCTS_DIR',includeInIndex=0)
hostproduct=add('hostproduct','PBXFileReference',explicitFileType='wrapper.application',path='macBitdo Driver.app',sourceTree='BUILT_PRODUCTS_DIR',includeInIndex=0)
productgroup=add('products','PBXGroup',children=[driverproduct,hostproduct],name='Products',sourceTree='<group>')
main=add('main','PBXGroup',children=[cpp,iig,hidcpp,hidiig,protocol,hostmain,ident('driverplist'),ident('driverent'),ident('hostplist'),ident('hostent'),productgroup],sourceTree='<group>')
shared={'DEVELOPMENT_TEAM':'B7MRCR9852','CODE_SIGN_STYLE':'Automatic','CODE_SIGN_IDENTITY':'Apple Development','GCC_TREAT_WARNINGS_AS_ERRORS':'YES','CLANG_ENABLE_MODULES':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}
driverconf=configs('driver',{**shared,'SDKROOT':'driverkit','SUPPORTED_PLATFORMS':'driverkit','DRIVERKIT_DEPLOYMENT_TARGET':'23.0','ARCHS':'arm64e','PRODUCT_NAME':'$(PRODUCT_BUNDLE_IDENTIFIER)','PRODUCT_BUNDLE_IDENTIFIER':'com.zbreilly.macBitdo.DriverHost.Receiver','INFOPLIST_FILE':'Driver/Info.plist','CODE_SIGN_ENTITLEMENTS':'Driver/Driver.entitlements','CLANG_CXX_LANGUAGE_STANDARD':'gnu++17','CLANG_CXX_LIBRARY':'libc++','GCC_ENABLE_CPP_EXCEPTIONS':'NO','GCC_ENABLE_CPP_RTTI':'NO','HEADER_SEARCH_PATHS':['$(SRCROOT)/Driver','$(DERIVED_FILE_DIR)'],'OTHER_LDFLAGS':['-framework','DriverKit','-framework','USBDriverKit','-framework','HIDDriverKit'],'SKIP_INSTALL':'YES'})
driver=add('driver','PBXNativeTarget',name='UltimateReceiverDriver',productName='UltimateReceiverDriver',productReference=driverproduct,productType='com.apple.product-type.driver-extension',buildConfigurationList=driverconf,buildPhases=[sources('driverSources',[cpp,iig,hidcpp,hidiig])],buildRules=[],dependencies=[])
copyfile=add('embedfile','PBXBuildFile',fileRef=driverproduct,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
embed=add('embed','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='$(CONTENTS_FOLDER_PATH)/Library/SystemExtensions',dstSubfolderSpec=16,files=[copyfile],name='Embed DriverKit Extension',runOnlyForDeploymentPostprocessing=0)
proxy=add('proxy','PBXContainerItemProxy',containerPortal=ident('project'),proxyType=1,remoteGlobalIDString=driver,remoteInfo='UltimateReceiverDriver')
dependency=add('dependency','PBXTargetDependency',target=driver,targetProxy=proxy)
hostconf=configs('host',{**shared,'SDKROOT':'macosx','SUPPORTED_PLATFORMS':'macosx','MACOSX_DEPLOYMENT_TARGET':'14.0','ARCHS':'arm64','PRODUCT_NAME':'macBitdo Driver','PRODUCT_BUNDLE_IDENTIFIER':'com.zbreilly.macBitdo.DriverHost','INFOPLIST_FILE':'Host/Info.plist','CODE_SIGN_ENTITLEMENTS':'Host/Host.entitlements','CLANG_ENABLE_OBJC_ARC':'YES','OTHER_LDFLAGS':['-framework','Foundation','-framework','AppKit','-framework','SystemExtensions'],'ENABLE_HARDENED_RUNTIME':'YES'})
host=add('host','PBXNativeTarget',name='macBitdo Driver',productName='macBitdo Driver',productReference=hostproduct,productType='com.apple.product-type.application',buildConfigurationList=hostconf,buildPhases=[sources('hostSources',[hostmain]),embed],buildRules=[],dependencies=[dependency])
project=add('project','PBXProject',attributes={'LastUpgradeCheck':'2700','TargetAttributes':{driver:{'DevelopmentTeam':'B7MRCR9852'},host:{'DevelopmentTeam':'B7MRCR9852'}}},buildConfigurationList=configs('project',{}),compatibilityVersion='Xcode 14.0',developmentRegion='en',knownRegions=['en','Base'],mainGroup=main,productRefGroup=productgroup,projectDirPath='',projectRoot='',targets=[host,driver])
def encode(value,level=0):
    if isinstance(value,dict):return '{\n'+''.join('\t'*(level+1)+json.dumps(str(k))+' = '+encode(v,level+1)+';\n' for k,v in value.items())+'\t'*level+'}'
    if isinstance(value,list):return '( '+', '.join(encode(v,level) for v in value)+' )'
    return str(value) if isinstance(value,int) else json.dumps(value)
p=root/'ReceiverDriver.xcodeproj';p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
info={'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'DEXT','CFBundleShortVersionString':'0.1','CFBundleVersion':'3','OSBundleUsageDescription':'Support the 8BitDo Ultimate 2.4 GHz USB receiver, controller input and rumble.'}
common={'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','IOUserServerName':'$(PRODUCT_BUNDLE_IDENTIFIER)','idVendor':0x2dc8,'idProduct':0x3106}
info['IOKitPersonalities']={'Receiver USB Device':{**common,'IOClass':'IOUserService','IOProviderClass':'IOUSBHostDevice','IOUserClass':'UltimateReceiverDevice','CFBundleIdentifierKernel':'com.apple.kpi.iokit','IOMatchCategory':'com.apple.null.driver'},'Receiver HID Interface':{**common,'IOClass':'AppleUserHIDDevice','IOProviderClass':'IOUSBHostInterface','IOUserClass':'UltimateReceiverHID','CFBundleIdentifierKernel':'com.apple.iokit.IOHIDFamily','bInterfaceNumber':0,'bConfigurationValue':1,'bInterfaceClass':255,'bInterfaceSubClass':0x5d,'bInterfaceProtocol':1}}
(root/'Driver/Info.plist').write_bytes(plistlib.dumps(info))
(root/'Driver/Driver.entitlements').write_bytes(plistlib.dumps({'com.apple.developer.driverkit':True,'com.apple.developer.driverkit.family.hid.device':True,'com.apple.developer.driverkit.transport.usb':[{'idVendor':'*'}],'com.apple.security.app-sandbox':True}))
(root/'Host/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleName':'macBitdo Driver','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.1','CFBundleVersion':'1','LSMinimumSystemVersion':'14.0','NSPrincipalClass':'NSApplication','NSSystemExtensionUsageDescription':'Install the USB/HID DriverKit driver for the 8BitDo Ultimate 2.4 GHz receiver.'}))
(root/'Host/Host.entitlements').write_bytes(plistlib.dumps({'com.apple.developer.system-extension.install':True}))
print(p)
