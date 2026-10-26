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

Then the z80 transforms the coordinates to determine where each object will be. 
It is not simply looking up planetary positions in a table. The Z80 calculates them from the date, time, orbital elements, and observer's location.


**Presenting the Z80 PLANET TRACKER**

<img width="232" height="243" alt="Z80_Planet_Tracker" src="https://github.com/user-attachments/assets/a6d47785-5d5a-419d-82ed-b2715915e830" />

The work flow is as follows:

Upon power up, the GPS starts recieving GPS data while the z80 does firmware initialization for the PIO. This enables the keypad and display.


A Splash screen is presented.<br/>
<img width="385" height="100" alt="Z_PLANET" src="https://github.com/user-attachments/assets/687ab5ef-2a2d-466c-a710-f97ce2d3a1b4" />

The piezo sounder plays its two-note startup chime.
After 10 seconds or the user pressing the ENTER key,  the Acquiring GPS Fix message is displayed.<br/>
<img width="385" height="100" alt="Acquiring" src="https://github.com/user-attachments/assets/052d9b45-8fe7-4f90-a95e-c0af0e96c725" />

  
Following a successful GPS fix,  another message is displayed: <br/>
<img width="385" height="100" alt="GPS_FIX" src="https://github.com/user-attachments/assets/ccb57135-ca97-4a5e-86f3-d35d56d9a505" />




In order to provide the user with their local time, 
 they are queried with a UTC OFFSET? screen,<br/>
 
 <img width="385" height="100" alt="UTC_OFFSET" src="https://github.com/user-attachments/assets/9e781f33-f0ae-409f-b8e5-76a242a5f527" />

which allows the user to select how far or behind their location is from UTC.

Next, they are presented with an OPTIONS? screen<br/>
This allows the user to decide which object they wish to calculate on.
(See image above for options)
 <img width="385" height="100" alt="Option_Screen" src="https://github.com/user-attachments/assets/63aba66b-a681-426b-b519-129c71453bb8" />

After their selection, the TRANZ330 has all the information needed to performs the calculation.
<img width="385" height="100" alt="Jupiter_Calc" src="https://github.com/user-attachments/assets/7b2b351f-68ce-4463-a13f-b829bc9394ab" />

When done, the display will tell if the object is VIS or NOT VIS (Visible or Not Visible) at the present time.

<img width="385" height="100" alt="Jupiter_no_Vis" src="https://github.com/user-attachments/assets/9593bcc1-82a4-4f92-ace6-fbac45417fed" />

Pressing the ENTER key cycles through the data. 

RISE TIME

<img width="385" height="100" alt="Rise" src="https://github.com/user-attachments/assets/7c70952f-1900-4c54-a599-44847ff2a76a" />

SET TIME

<img width="385" height="100" alt="Set" src="https://github.com/user-attachments/assets/fa3581e5-5b5c-4f5f-ad9b-5f25857568b7" /><br/>
AZIMUTH (compass heading)<br/>
<img width="385" height="100" alt="AZIMUTH" src="https://github.com/user-attachments/assets/9f8c87c3-4467-4c1c-b8a6-80bc05fe37ac" />

 ELEVATION (degrees above or below the horizon)<br/>
<img width="385" height="100" alt="Elevation" src="https://github.com/user-attachments/assets/a2042587-a144-406e-a069-cc9c9c01d958" />



DATE and TIME (local time)<br/>
<img width="385" height="100" alt="Date_Time" src="https://github.com/user-attachments/assets/06a543a4-76ad-4b8a-b2b0-04c6c3de04d8" />

LATITUDE and LONGITUDE (location of the user)<br/>
<img width="385" height="100" alt="Lat_Lon" src="https://github.com/user-attachments/assets/39f6ca6a-0247-4d48-88f5-30c97c67c854" />

A PRINT screen is provided and has a default answer of NO so that pressing ENTER restarts the cycle.<br/>
<img width="385" height="100" alt="Print_Yes" src="https://github.com/user-attachments/assets/4f73346c-4c75-4515-add3-bbc87e2dc88d" />
PRESSING the * key selects YES and pressing ENTER advances to the next printing screen.




PRINT NOW? is displayed and pressing ENTER initiates the print out. 
Pressing the * key selects NO and pressing ENTER advances to the 
DATE and TIME screen which allows the user to select a date in which to calculate on.  
This would be handy if, during the day,  you wanted to print out a planet's information for later that evening.
A print out consists of the OBJECT's name, its visibility, the LAT and LON for that location, Date and TIME (in UTC),
and the AZIMUTH and ELEVATION for that event.  <img width="150" height="200" alt="Saturn_Ticket" src="https://github.com/user-attachments/assets/eab12771-074d-499d-9169-d5bb32936db5" /> Sample printout of a 'ticket' to the show.

What was cool about this project and made it easy to accomplish was that the TRANZ330 had an 32 kb UV-EPROM.
This made firmware changes easy.
I could of made an EEPROM (Electrically Eraseable PROM) using an Atmel AT28C256, but other components got in the way.
Erasing and Programming UV EPROMs is only considered cool in certain circles,  but if you can get and UV chip eraser and a programmer you can join!
I had acquired a old/used UV lamp from a hospital and had a GQ-4x4 USB EPROM programmer from previous projects builds. 

This would be a great place to thank OshonSoft for their Z80 simulator.  It came in real handy since it can simulate a display and keypad. 
I would have had to burn many, many more ROMS otherwise. THANKS!

Also like to thank Big Mess O' Wires who did all the ground work for mapping out the TRANZ330
and Mike Ingle, author of the verbanner.c program which allowed me to add the cool logo to the event tickets.








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
