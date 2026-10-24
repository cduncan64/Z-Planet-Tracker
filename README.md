# Z-Planet-Tracker
VERIFONE TRANZ330 Point-Of-Sale machine Based Planet Location Calculator.  
By no means is this an accurate astronomy device.  
This program was to demonstrate the capabilities of vintage hardware.

A TRANZ330 is a Point-Of-Sale machine popular in the United States (other countries maybe) in the 1990s.  
<img width="150" height="200" alt="TRANZ330_Hello" src="https://github.com/user-attachments/assets/255b047b-73a1-47a8-b2f1-fefae0b7f673" />

The TRANZ330 uses a Z80 CPU running at 8mhz.  
It has 32k of RAM and 32k of ROM on a UV programmable 27C256 EEPROM. <--- Nice!
It displays on a 16 character vacuum fluorescent display (VFD) driven by a OKI C1937-01 display driver that uses a serial interface.
It has two serial port operating at 9600 normally. The serial ports are used for an external printer or a barcode reader or pin pad. 
I used one serial port to receive data from a GPS module and also to transmit to the printer.

<img width="150" height="200" alt="MainBoard" src="https://github.com/user-attachments/assets/e6f24863-1016-44a0-b5ba-90dbd9d759a0" />The mainboard of the TRANZ330.


<img width="150" height="200" alt="20260830_152134" src="https://github.com/user-attachments/assets/5284b667-5bdd-4d6e-ae9a-6258958a8408" />Its handy to have an UV EEPROM. 


The printer I used is the Verifone Printer 250.  
<img width="150" height="200" alt="Printer250" src="https://github.com/user-attachments/assets/228092b9-7eb7-44a6-974a-d11a4f18a55c" />
It is a thermal printer that can print in two colors (RED and BLACK).

It can also do bit map images in addition to characters.

NOTE: The serial ports are RS232 and not TTL.  

<img width="150" height="200" alt="GPS_Module" src="https://github.com/user-attachments/assets/76ada275-368f-419d-b9d1-33a6944180dd" />



Since the GPS module is a TTL 5 vdc device, I had to make a GPS module that shifted the GPS information to RS232 levels.
A MAX3232 IC was used for the conversion.  
The transmit side of the serial port was passed though and connected to the printer. 
The GPS module has an external connector for an outdoor antenna.  Although the GPS can acquire a fix inside my house,  it is faster 
with the external antenna.

There is no 5 volt dc on the serial port I used.  
<img width="150" height="200" alt="BodgeWire" src="https://github.com/user-attachments/assets/b801f42e-4538-4647-8745-712a3b7ac4f5" />
Since pin 8 of the DIN connector was unused, I bodge wired it to a 5 volt trace on the pcb.


The GPS provides the Location, Date and Time data that is used for the low-precision Keplerian orbital calculations.

 Then transforms the coordinated to determine where each object will be. 
It is not simply looking up planetary positions in a table. The Z80 calculates them from the date, time, orbital elements, and observer's location.



MORE STUFF GOES HERE!

<img width="150" height="200" alt="Saturn_Ticket" src="https://github.com/user-attachments/assets/eab12771-074d-499d-9169-d5bb32936db5" />
The printer is used to create a 'ticket' to the show.





Resources

https://www.bigmessowires.com/2011/05/10/mapping-the-tranz-330/

https://www.confidantmail.org/wordpress/index.php/2017/09/09/hack-a-receipt-printer-to-print-mini-banners/

https://www.confidantmail.org/download/verifone250manual.pdf

https://www.possupply.com/sca/pdf/Verifone/VeriFone-TRANZ-330-User-Manual.pdf

Disclaimer: I used chatGPT (because I suck at z80 assembler. Well not just z80 assembler, any assembler for that matter, and not just assembler, also c++, Python, ... 
Truth: I can program, but have never messed with the z80 in assembler.  ( I have a PIC assembler background.) 
Could I have learned z80 assembler?  Sure!  But not in time for the Hackaday Retro Computing Challenge. 
Again,  this project was used to demonstrate the capabilities of a device that uses 30+ year old hardware.  
Was it fun? Yes! 
Was it challenging?  Yes!  
Did I learn about z80 assembler? A bit. 
(pun intended)
