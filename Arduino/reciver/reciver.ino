#include <SPI.h> 
#include <nRF24L01.h> 
#include <RF24.h> 
#define CE_PIN 8 
#define CSN_PIN 7 
RF24 radio(CE_PIN, CSN_PIN); 
const byte address[6] = "00001"; 
struct Data_Packet { int xVal; int yVal; }; 
Data_Packet data; 
void setup() 
  { 
    Serial.begin(9600); // <-- MONITOR THIS!
    radio.begin(); 
    radio.setPALevel(RF24_PA_LOW); 
    radio.setDataRate(RF24_250KBPS); 
    radio.openReadingPipe(0, address); 
    radio.startListening();
    Serial.println("Receiver ready... waiting for data"); 
    } 
    
    void loop() { 
      if (radio.available()) 
        { radio.read(&data, sizeof(Data_Packet)); 
          Serial.print("X: "); Serial.print(data.xVal); 
          Serial.print(" Y: "); Serial.println(data.yVal); 
        } 
        delay(50); 
    }

    //LETS SEE IF THE UPDATES REALLY WORK!!!!!!!