#!/usr/bin/ruby
require 'json'
require 'uri'
require 'net/http'
require 'date'

puts "Content-type: text/html\n\n";

@threshold   = 0.0
# these numbers ended up being pretty arbitrary. seems like long enough.
@on_timeout  = 1.0 * 24.0/60.0/60.0/60.0
@off_timeout = 1.0 * 24.0/60.0/60.0/60.0

@sms_uri = URI('http://127.0.0.1:9090/text')

@state = JSON.parse(File.read('washer_state.json'))
@oklist = JSON.parse(File.read('oklist.json'))

args = ENV['QUERY_STRING'].split('&').each_with_object({}) do |q, obj|
    k,v = q.split('=')
    obj[k] = v
end

def outlet_state
    uri = URI("http://#{@state['plug_ip']}?m=1")
    res = Net::HTTP.get_response(uri)
    # do something unless res.is_a?(Net::HTTPSuccess) 
    {
        'switch' => res.body.split("'>")[1].split('<')[0],
        'power' => res.body.split(/{.}/)[6][0..-2].to_f
    }
end

def toggle_outlet
    uri = URI("http://#{@state['plug_ip']}?m=1&o=1")
    res = Net::HTTP.get_response(uri)
end

def turn_on
    while outlet_state['switch'] != 'ON' do
        toggle_outlet
        sleep(0.5)
    end
end

def turn_off
    while outlet_state['switch'] != 'OFF' do
        toggle_outlet
        sleep(0.5)
    end
end

def check_oklist(phone)
    return true if @oklist[phone]

    puts "Phone #{phone} not in OKList"
end

def start(phone)
    unless @state['status'] == 'IDLE'
        puts "Washer already assigned to #{@oklist[@state['phone']][0]}"
        return
    end

    check_oklist(phone) || return

    @state['phone'] = phone
    @state['on_time'] = Time.now.to_datetime
    @state['status'] = 'WAITING'

    turn_on

    puts "<div style=\"font-size: 64px;\">The washer is turned on for #{@oklist[phone][0]} and will alert #{phone} when it stops.</div>"
end

def poll
    case @state['status']
    when 'IDLE'
        # do nothing
    when 'WAITING'
        if outlet_state['power'] > @threshold
            @state['on_time'] = Time.now.to_datetime
            @state['status'] = 'RUNNING'
            alert_turned_on
        elsif Time.now.to_datetime > DateTime.strptime(@state['on_time'], '%Y-%m-%dT%H:%M:%S%z') + @on_timeout
            alert_not_started
            @state['on_time'] = nil
            @state['phone'] = nil
            @state['status'] = 'IDLE'
            turn_off
        end
    when 'RUNNING'
        if outlet_state['power'] > @threshold
            @state['on_time'] = Time.now.to_datetime
        elsif Time.now.to_datetime > DateTime.strptime(@state['on_time'], '%Y-%m-%dT%H:%M:%S%z') + @off_timeout
            alert_completed
            @state['on_time'] = nil
            @state['phone'] = nil
            @state['status'] = 'IDLE'
            turn_off
        end
    end

    puts @state['status']
end

def reset
    @state['on_time'] = nil
    @state['phone'] = nil
    @state['status'] = 'IDLE'

    turn_off

    puts @state['status']
end

def alert(message)
    res = Net::HTTP.post_form(@sms_uri, 'number' => @state['phone'], 
                                        'carrier' => @oklist[@state['phone']][1], 
                                        'message' => message)
end

def alert_turned_on
    alert("Washer turned on at #{Time.now.to_s[0..15]}.  You will be alerted when it stops.")
end

def alert_not_started
    alert('The washer did not turn on in time. Please scan your code again.')
end

def alert_completed
    alert("Your wash is complete at #{Time.now.to_s[0..15]}.")
end

def qr_codes
    require 'rqrcode'

    html = File.open("/tmp/qrcodes.html", 'w')
    html.puts('<html><style>table {page-break-inside: avoid;} .c1 { width: 240px; text-align: right; vertical-align: middle; font-size: 64px } .c2 { width: 210px; height: 225px; }</style><table><tr>')

    args = {
        module_px_size: 4
    }

    i=1
    @oklist.each do |phone, (name, _carrier)|
        png = RQRCode::QRCode.new("http://#{@state['server_ip']}/cgi-bin/washer.rb?cmd=start&phone=#{phone}").as_png(args)
        imgfile = "/tmp/qrcode-#{name}.png"
        IO.binwrite(imgfile, png.to_s)

        html.puts("<td class=\"c1\">#{name}</td><td class=\"c2\"><img src=\"#{imgfile}\" /></td>")
        html.puts("</tr><tr>") if (i+=1).odd?
    end

    png = RQRCode::QRCode.new("http://#{@state['server_ip']}/cgi-bin/washer.rb?cmd=reset").as_png(args)
    imgfile = '/tmp/qrcode-Reset.png'
    name = 'Reset'
    IO.binwrite(imgfile, png.to_s)

    html.puts("</tr><tr><td class=\"c1\">#{name}</td><td class=\"c2\"><img src=\"#{imgfile}\" /></td></tr>")

    html.puts('</table></html>')
    html.close
end

case args['cmd']
when 'start'
    start(args['phone']&.gsub(/[^\d]/,''))
when 'poll'
    poll
when 'reset'
    reset
when 'on'
    turn_on
when 'status'
    outlet_state
when 'codes'
    qr_codes
end

File.write 'washer_state.json', @state.to_json

exit 0
