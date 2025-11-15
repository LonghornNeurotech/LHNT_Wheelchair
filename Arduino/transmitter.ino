#include <SPI.h> #include <nRF24L01.h> 
#include <RF24.h> #define VRX A5 // Joystick X-axis (left/right) 
#define VRY A4 // Joystick Y-axis (up/down) 
#define CE_PIN 8 #define CSN_PIN 7 RF24 radio(CE_PIN, CSN_PIN); 
const byte address[6] = "00001"; // must match receiver 

struct Data_Packet 
  { int xVal; 
    int yVal; 
  }; 
Data_Packet data; 

void setup() 
{ 
  pinMode(VRX, INPUT); pinMode(VRY, INPUT); 
  radio.begin(); 
  radio.openWritingPipe(address); 
  radio.setPALevel(RF24_PA_LOW); // safer for bench testing 
  radio.stopListening(); // we're transmitting 
} 
void loop() { 
  data.xVal = analogRead(VRX) - 511; // centered around 0 
  data.yVal = analogRead(VRY) - 511; // centered around 0
  radio.write(&data, sizeof(Data_Packet)); delay(20); // adjust if needed (50Hz loop is smooth) 
}

//THESE ARE NEW UPDATES TESTING IF GIT PUSH WAS SUCESSFUL