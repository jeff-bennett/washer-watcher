# Washer Watcher
Ruby server script to watch a CloudFree Smart Plug connected to a washing machine and alert the user via SMS when it is done with a load.

## Notes
This was created in a weekend in response to my wife wanting to be alerted when the washing machine was done with a load.  Since we have six adults in the family I decided to make something that would alert whoever started the load when their load was complete.  I started by trying to make my own energy monitor ESPHome module but that did not work, so I used a CloudFree Smart Plug 2 with Tasmota.

My machine is already running Nginx, Docker, and Home Assistant.  My experience with Home Assistant is limited and I'm guessing I could have leveraged it better, but this is what I did.  Be kind with suggestions and questions.

## Installation
### CGI
Set up fastcgiwrap according to the instructions at https://www.howtoforge.com/serving-cgi-scripts-with-nginx-on-debian-squeeze-ubuntu-11.04-p3
~~~~
  server {
    listen 9191;
    listen [::]:9191;
    allow all;
    server_name washer.local;
    location /cgi-bin/ {
      # Disable gzip (it makes scripts feel slower since they have to complete
      # before getting gzipped)
      gzip off;
      # Set the root to /usr/lib (inside this location this means that we are
      # giving access to the files under /usr/lib/cgi-bin)
      root  /usr/lib;
      # Fastcgi socket
      fastcgi_pass  unix:/var/run/fcgiwrap.socket;
      # Fastcgi parameters, include the standard ones
      include /etc/nginx/fastcgi_params;
      # Adjust non standard parameters (SCRIPT_FILENAME)
      fastcgi_param SCRIPT_FILENAME  $document_root$fastcgi_script_name;
    }
  }
~~~~

###Code
Copy the contents of the cgi-bin directory from the repository to your cgi-bin directory.  Edit the washer_state.json file and set the IP address of your smart plug in the plug_ip field and the local network address of your cgi-bin server in the server_ip field.

###TextBelt
TextBelt is an SMS gateway.  If you don't want to self-host there is a free one-per-day level and the paid levels are very reasonably priced.

I used the instructions on the TextBelt docker page https://github.com/hexeth/textbelt-docker, with some small differences.  I added the -d param to run the containter as a daemon and I had to change imap.gmail.com to smtp.gmail.com.

~~~~
docker run -d --name=textbelt \
-p 9090:9090 \
-e HOST=smtp.gmail.com \
-e MAIL_PORT=587 \
-e MAIL_USER=myaddress@gmail.com \
-e MAIL_PASS=password \
-e FROM_ADDRESS=myaddress@gmail.com \
-e REALNAME=washingmachine \
-e MAIL_DEBUG=false \
-e SECURE_CONNECTION=true \
--restart unless-stopped \
hexeth/textbelt-docker
~~~~

###OK List
Only phone numbers in the oklist.json file will be allowed to start the washer.  Edit the file to add each family member, their name, and their phone carrier from this list from TextBelt https://github.com/typpo/textbelt/blob/master/lib/carriers.js.  Ensure that there is no trailing comma on the last item in the list or the script will fail.

###QR Codes
Install rqrcode with "gem install rqrcode".  https://github.com/whomwah/rqrcode

Browse to http://[server_ip]/cgi-bin/washer.rb?cmd=codes to generate QR codes and a printable HTML page in the /tmp/ directory.  This can be printed and cut apart into a booklet.  I tried printing it as one page but it was difficult to get my qr code reader to focus on the intended code.

###Home Assistant
I use Home Assistant to periodically poll the washer and trigger the timeout and complete events.  I added the following to ~/.home-assistant/configuration.yaml and restarted Home Assistant.  I also added the sensor to my lovelace home page but I don't know if that is strictly necessary.  There are other ways to poll this but that's what I did.

~~~~
sensor:
  - platform: rest
    resource: http://[server ip address/127.0.0.1 depending on how homeassistant is running]:9191/cgi-bin/washer.rb?cmd=poll
    name: wash_watcher
~~~~

##Usage
Plug the washing machine into the smart plug.  Scan your QR code and the outlet will turn on and wait for a few moments for the washer to start consuming power.  If the washer does not start in a reasonable amount of time you will receive an alert to that effect.  If it starts you will get an alert saying it's started and then once the outlet stops consuming power you will receive a final alert and the outlet will turn itself off.

###API
There's not much to it.  Look around lines 212-225 and this doc for an idea.




https://www.youtube.com/watch?v=GZnA4jHuyzs
