/*
 
 File: ViewController.m
 
 Abstract: View Controller to select whether the App runs in Central or
 Peripheral Mode
 
 Version: 1.0
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by
 Apple Inc. ("Apple") in consideration of your agreement to the
 following terms, and your use, installation, modification or
 redistribution of this Apple software constitutes acceptance of these
 terms.  If you do not agree with these terms, please do not use,
 install, modify or redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc.
 may be used to endorse or promote products derived from the Apple
 Software without specific prior written permission from Apple.  Except
 as expressly stated in this notice, no other rights or licenses, express
 or implied, are granted by Apple herein, including but not limited to
 any patent rights that may be infringed by your derivative works or by
 other works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2012 Apple Inc. All Rights Reserved.
 
 */

#import "ViewController.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "TransferService.h"


@interface ViewController () <CBCentralManagerDelegate, CBPeripheralDelegate>

@property (weak, nonatomic) IBOutlet UILabel *statusTextLabel;
@property (weak, nonatomic) IBOutlet UIButton *connectButtonTextLabel;

@property (strong, nonatomic) CBCentralManager      *centralManager;
@property (strong, nonatomic) CBPeripheral          *discoveredPeripheral;
@property (strong, nonatomic) CBCharacteristic      *discoveredCharacteristic;
@property (strong, nonatomic) NSMutableData         *data;

@end




@implementation ViewController

- (IBAction)connectButton:(UIButton *)sender {
    
    if (!self.discoveredPeripheral.state == (bool)CBPeripheralStateConnected) {
        [self scan];
        return;
    }
    
    [self cleanup];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    _data = [[NSMutableData alloc] init];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}


//MESH DEVICE BUTTON CONTROLS
- (IBAction)onButton1:(UIButton *)sender {
    [self sendMeshData:255 forNode:1000];
}
- (IBAction)offButton1:(UIButton *)sender {
    [self sendMeshData:100 forNode:1000];
}
- (IBAction)onButton2:(UIButton *)sender {
    [self sendMeshData:255 forNode:2000];
}
- (IBAction)offButton2:(UIButton *)sender {
    [self sendMeshData:100 forNode:2000];
}
- (IBAction)deviceSlider:(UISlider *)sender {
    int sliderValue = (int)(sender.value * 255);
    //TODO - Don't respond to continous event updates
    //[self sendMeshData:sliderValue forNode:3000];
}




//CENTRAL METHODS

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (central.state != CBCentralManagerStatePoweredOn) {
        [self setStatusDisconnected];
    }
}


//Scan for all peripherals
- (void)scan
{
    [self.centralManager scanForPeripheralsWithServices:nil options:@{ CBCentralManagerScanOptionAllowDuplicatesKey : @YES }];
    [self setStatus:@"Scanning started..."];
}


//Called as soon as any nearby BLE device is found, then we connect to the device
//TODO - Filter only fruity mesh devices
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    // Reject any where the value is above reasonable range
    if (RSSI.integerValue > -15) {
        return;
    }
    
    // Reject if the signal strength is too low to be close enough (Close is around -22dB)
    if (RSSI.integerValue < -55) {
        return;
    }
    
    NSLog(@"Discovered %@ at %@", peripheral.name, RSSI);
    
    // Ok, it's in range - have we already seen it?
    if (self.discoveredPeripheral != peripheral) {
        
        // Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it
        self.discoveredPeripheral = peripheral;
        
        // And connect
        NSLog(@"Connecting to peripheral %@", peripheral);
        [self.centralManager connectPeripheral:peripheral options:nil];
    }
}


/** If the connection fails for whatever reason, we need to deal with it.
 */
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"Failed to connect to %@. (%@)", peripheral, [error localizedDescription]);
    [self cleanup];
}


//After connecting we look for the first available service
//TODO - Filter only fruity mesh service
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    [self setStatus:@"Peripheral Connected"];
    
    // Stop scanning
    [self.centralManager stopScan];
    NSLog(@"Scanning stopped");
    
    // Clear the data that we may already have
    [self.data setLength:0];
    
    // Make sure we get the discovery callbacks
    peripheral.delegate = self;
    
    // Search for all services
    [peripheral discoverServices:nil];
}


//When the first service is discovered, find the associated characterisitics
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if (error) {
        NSLog(@"Error discovering services: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }
    
    // Just pick the first available service - workaround due to how the fruity mesh services are working now
    CBService *service = peripheral.services[0];
    NSLog(@"Discovering characteristics for service: %@", service);
    [peripheral discoverCharacteristics:nil forService:service];
    
}


// A characteristic was discovered.
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    // Deal with errors (if any)
    if (error) {
        NSLog(@"Error discovering characteristics: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }
    
    // Again, pick the first characteristic - more workarounds
    CBCharacteristic *characteristic = service.characteristics[0];
    _discoveredCharacteristic = characteristic;
    NSLog(@"Found characteristic: %@", characteristic);
    
    
    NSData *handShakeInitData;
    handShakeInitData = [@"N 001 5000" dataUsingEncoding:NSUTF8StringEncoding];
    [peripheral writeValue:handShakeInitData forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
}

//Called after our initial handShakeInitData write has been received, so now we send the handShake ACK
- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    NSLog(@"Handshake callback was received");
    NSData *handShakeAckData;
    handShakeAckData = [@"N 001 5000" dataUsingEncoding:NSUTF8StringEncoding];
    [peripheral writeValue:handShakeAckData forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
    [self setStatus:@"Connected to Mesh"];
}



//If a disconnection happens, we need to clean up our local copy of the peripheral and characteristic
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"Peripheral Disconnected");
    self.discoveredPeripheral = nil;
    self.discoveredCharacteristic = nil;
    
    [self setStatusDisconnected];
}


// Call this when things either go wrong, or you're done with the connection.
- (void)cleanup
{
    // Don't do anything if we're not connected, otherwise cancel connection
    if (!self.discoveredPeripheral.state == (bool)CBPeripheralStateConnected) {
        return;
    }
    
    [self.centralManager cancelPeripheralConnection:self.discoveredPeripheral];
    [self setStatusDisconnected];
}


- (void)setStatusDisconnected {
    NSString *connectionStatus = @"Disconnected";
    _statusTextLabel.text = connectionStatus;
    NSLog(@"%@", connectionStatus);
    [_connectButtonTextLabel setTitle:@"CONNECT" forState:UIControlStateNormal];
}


- (void)setStatus:(NSString *) connectionStatus {
    _statusTextLabel.text = connectionStatus;
    NSLog(@"%@", connectionStatus);
    [_connectButtonTextLabel setTitle:@"DISCONNECT" forState:UIControlStateNormal];
}

-(void)sendMeshData:(int)dataValue forNode:(int)nodeId{
    NSArray *meshDataComponents = @[@"N", [NSString stringWithFormat:@"%d", dataValue], [NSString stringWithFormat:@"%d", nodeId]];
    NSString *meshDataString = [meshDataComponents componentsJoinedByString:@" "];
    NSData *meshData = [meshDataString dataUsingEncoding:NSUTF8StringEncoding];
    
    NSLog(@"Sent data: %@", meshDataString);
    [_discoveredPeripheral writeValue:meshData forCharacteristic:_discoveredCharacteristic
                                 type:CBCharacteristicWriteWithoutResponse];
}

@end
