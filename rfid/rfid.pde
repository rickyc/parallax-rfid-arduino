/**
 * RFID Door
 *
 * author Benjamin Eckel
 * date 10-17-2009
 * http://www.gumbolabs.org/2009/10/17/parallax-rfid-reader-arduino/
 *
 * modified by Ricky Cheng
 * Added code to add / remove rfid tags from the eeprom.
 * date 01-19-2010
 */
 
#define RFID_ENABLE 2         // to RFID ENABLE

#define CODE_LEN 10           // Max length of RFID tag

#define VALIDATE_LENGTH  200  // maximum reads b/w tag read and validate
#define ITERATION_LENGTH 2000 // time, in ms, given to the user to move hand away
#define START_BYTE 0x0A 
#define STOP_BYTE 0x0D

#define MAX_NUM_KEYS 25

#include <EEPROM.h>

// RFID tag being read
char tag[CODE_LEN];

// This is the add new card unique identifer.
char insertion_tag[] = "0425EFAF80";

// This is the delete cards unique identifier
char deletion_tag[] = "0F03056A43";

void setup() { 
  // Uncomment this if you want to clear the eeprom
  // clearEEPROM();

  // Debug method to print out the rfid tags currently stored in the eeprom
  printRegisteredKeys();
  pinMode(RFID_ENABLE, OUTPUT);
}
 
// This is the main run loop.
void loop() { 
  enableRFID(); 
  
  blockAndGetRFIDTag();
  
  if (isCodeValid()) {
    // if we were previously in insert or delete mode
    // then skip the unlock door check
    boolean unlockDoorCheck = true;
    disableRFID();
    
    if (checkForInsertTag()) unlockDoorCheck = false;
    if (checkForDeleteTag()) unlockDoorCheck = false;
    
    if (unlockDoorCheck) {
      if (currentKeyInMemory()) {
        Serial.println("Door unlocked! Add code to trigger a relay or servo motor");
      } else {
        Serial.println("Unauthorized RFID card.");
      }
    }
    delay(ITERATION_LENGTH);
  } else {
    disableRFID();
    Serial.println("Got some noise.");
  }
  
  Serial.flush();
  clearCode();
}

// Clears out the memory space for the tag to 0s.
void clearCode() {
  for(int i=0; i<CODE_LEN; i++)
    tag[i] = 0;
}

// Print the rfid tag that was just read.
void printTag() {
  Serial.print("Tag: ");  
  for(int i=0; i<CODE_LEN; i++) {
    Serial.print(tag[i]); 
  }
  Serial.println();
}

/**
 * Check to see if the insert tag was read.
 * If it was then change the rfid into add new 
 * tag mode.
 */
boolean checkForInsertTag() {
  printTag();
  
  if (isInsertTag()) {
    disableRFID();
    Serial.flush();
    clearCode();
    
    Serial.println("Add new card mode.");
   
    // give some room for the user to move away their hand
    delay(ITERATION_LENGTH);
    Serial.println("Waiting....");
    
    enableRFID();
    blockAndGetRFIDTag();
    if(isCodeValid()) {
      printTag();
      addTag();
    }
   
    Serial.println("Exit add new card mode.");
    return true;
  }

  return false;
}

boolean checkForDeleteTag() {
  printTag();
  
  if (isDeleteTag()) {
    disableRFID();
    Serial.flush();
    clearCode();
    
    Serial.println("Staring deletion mode.");
    
    // give some room for the user to move away their hand
    delay(ITERATION_LENGTH);

    Serial.println("Waiting");
    
    enableRFID();
    blockAndGetRFIDTag();
    if (isCodeValid()) {
      deleteTag();
      Serial.println("Deleted Tag...");
      printTag();
      Serial.println("--------------");
    } else {
      Serial.print("Card was invalid."); 
    }
    
    Serial.println("Ending deletion mode.");   
    return true;
  }

  return false;
}

void deleteTag() {
  // should return -1 to maximum number of tags
  int idx = indexOfKeyInMemory();
  Serial.print("Removing card at index: ");
  Serial.println(idx);

  // if there are no tags in eeprom skip this statement 
  if (idx != -1) {
    Serial.println("There are keys to be removed.");
    int totalKeys = getNumKeys();
    
    // if there is only one tag, then erase the whole eeprom
    if (totalKeys == 1) {
      Serial.println("Only one key to delete. Remove all of them.");
      clearEEPROM();
    } else { // otherwise shift everything over by one spot
      Serial.println("Shift tags over by one tag.");

      for (int i=idx; i<totalKeys-1; i++) {
        for (int j=0; j<CODE_LEN; j++) {
          char c = EEPROM.read((i+1)*CODE_LEN+j);
          EEPROM.write((i*CODE_LEN)+j,c);
        }
      }
  
      EEPROM.write(511, totalKeys-1);
      Serial.println("Shifting ended.");
    }
  }
}

/**************************************************************/
/********************   RFID Functions  ***********************/
/**************************************************************/
void enableRFID() {
 digitalWrite(RFID_ENABLE, LOW);    
}
 
void disableRFID() {
 digitalWrite(RFID_ENABLE, HIGH);  
}

void blockAndGetRFIDTag() {
 block();
 getRFIDTag();  
}

// By default it should block until an rfid tag is read
void block() {
  while(Serial.available() <= 0) {}  
}

// Blocking function, waits for and gets the RFID tag.
void getRFIDTag() {
  byte next_byte; 
  
  if ((next_byte = Serial.read()) == START_BYTE) {      
    byte bytesread = 0; 
    while(bytesread < CODE_LEN) {
      if(Serial.available() > 0) { //wait for the next byte
        if((next_byte = Serial.read()) == STOP_BYTE) break;       
        tag[bytesread++] = next_byte;                   
      }
    }                
  }    
}
 
/**
 * Waits for the next incoming tag to see if it matches
 * the current tag.
 */
boolean isCodeValid() {
  byte next_byte; 
  int count = 0;
  while (Serial.available() < 2) {  //there is already a STOP_BYTE in buffer
    delay(1); //probably not a very pure millisecond
    if(count++ > VALIDATE_LENGTH) return false;
  }
  Serial.read(); //throw away extra STOP_BYTE
  if ((next_byte = Serial.read()) == START_BYTE) {  
    byte bytes_read = 0; 
    while (bytes_read < CODE_LEN) {
      if (Serial.available() > 0) { //wait for the next byte      
          if ((next_byte = Serial.read()) == STOP_BYTE) break;
          if (tag[bytes_read++] != next_byte) return false;                     
      }
    }                
  }
  return true;   
}

// Set the last EEPROM memory address to the number of tags currently stored
// in memory.
void setNumKeys(byte b) {
  EEPROM.write(511, b);
} 

// Retrieve the number of tags stored in EEPROM from address 511
byte getNumKeys() {
  return EEPROM.read(511);
}

// Printing out all the keys that are currently stored in EEPROM.
void printRegisteredKeys() {
  Serial.println("Start printing keys in EEPROM");
  byte num_keys = getNumKeys();
  Serial.print("Currently there are ");
  Serial.print(num_keys, DEC);
  Serial.println(" keys");
   
  for (int key_index=0; key_index<getNumKeys(); key_index++) {
    Serial.print("Tag ");
    Serial.print("#");
    Serial.print(key_index);
    Serial.print(": ");
    for(int j=key_index*CODE_LEN;j<(key_index+1)*CODE_LEN;j++) {
      Serial.print(EEPROM.read(j));
    }
    Serial.println();
  }
  Serial.println("End printing keys in eeprom");
}

// Add a new rfid tag to the eeprom.
void addTag() {
  byte num_keys = getNumKeys();
  int inc_num_keys = num_keys + 1;
  
  // do not allow the insertion or deletion card to be added to 
  // eeprom, if we are trying to add more than the maximum number 
  // of tags allowed
  if (isInsertTag() || isDeleteTag() || currentKeyInMemory() 
      || inc_num_keys >= MAX_NUM_KEYS) return ;
  
  Serial.print("Currently there are ");
  Serial.print(num_keys, DEC);
  Serial.println(" keys");
   
  // get the real address of the key in memory
  byte real_address = CODE_LEN*num_keys;
  // store the current tag there 
  for(int i=0; i<CODE_LEN; i++) {
    EEPROM.write(real_address+i, tag[i]);
  }
    
  Serial.print("Key added"); 
  printTag();
  Serial.println("------");

  // increment the number of keys
  setNumKeys(inc_num_keys);
}

// to get the first key, call getKey(0) etc.
// could use pointer for storage here
void getKey(int key_address,  byte storage[]) {
  // get real address
  byte real_address = CODE_LEN*key_address;
  for(int i = 0; i < CODE_LEN; i++) {
    storage[i] = EEPROM.read(real_address+i);
  }
}
 
//clears memory out if needed, replace 0 with whatever
void clearEEPROM() {
  for (int i = 0; i < 512; i++) EEPROM.write(i, 0); 
}

// Checks the keys in EEPROM to see if current key [tag] matches a valid key.
boolean currentKeyInMemory() {
  Serial.println("Checking if key is in eeprom.");
  
  for(int key_index=0; key_index<getNumKeys(); key_index++) {
    Serial.print("Checking card - ");
    Serial.println(key_index);
    if (compareKeys(key_index*CODE_LEN)) return true;      // found a match
  }
  return false;  // no matches
}

// Looks for the index of the current rfid tag scanned in the eeprom.
int indexOfKeyInMemory() {
  Serial.println("Initialize Index Check.");  
  for(int key_index=0; key_index<getNumKeys(); key_index++) {
    if (compareKeys(key_index*CODE_LEN)) return key_index;      // found a match
  }
  return -1;  // no matches
}

// Compares one key with current key.
boolean compareKeys(int key_index) {
  for(int j=0; j<CODE_LEN; j++) {
    if(EEPROM.read(j+key_index) != tag[j]) return false;  // not a match  
  }
  return true;   // all must have gone well
}

// ----------------------------
// check insert and delete
boolean isInsertTag() {
  for(int i=0;i<CODE_LEN;i++) {
    if (tag[i] != insertion_tag[i]) return false;
  }
  return true;
}

boolean isDeleteTag() {
  for(int i=0;i<CODE_LEN;i++) {
    if (tag[i] != deletion_tag[i]) return false;
  }
  return true;
}
