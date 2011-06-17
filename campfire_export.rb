require 'rubygems'
require 'time'
require 'fileutils'
require 'httparty'
require 'nokogiri'
require 'pp'

###
#
# Script configuration - all options are required.

start_date = Date.civil(2010, 1, 1)   # 1) Set the export start date
end_date   = Date.civil(2010, 12, 31) # 2) Set the export end date, inclusive
api_token  = ''                       # 3) Your API token goes here 
                                      #    (see "My Info" in Campfire)
subdomain  = ''                       # 4) Your Campfire subdomain goes here
                                      #    (e.g., 'mycompany')
#
#
###

base_url = "https://#{subdomain}.campfirenow.com"

def get(path, params = {})
  HTTParty.get "#{base_url}#{path}",
    :query      => params,
    :basic_auth => {:username => api_token, :password => 'X'}
end

def username(id)
  @usernames     ||= {}
  @usernames[id] ||= begin
    doc = Nokogiri::XML get("/users/#{id}.xml").body
    doc.css('name').text
  end
end

def message_to_string(message)
  user = username message.css('user-id').text
  type = message.css('type').text
  
  body = message.css('body').text
  time = Time.parse message.css('created-at').text
  prefix = time.strftime '[%H:%M:%S]'
  
  case type
  when 'EnterMessage'
    "#{prefix} #{user} has entered the room"
  when 'KickMessage', 'LeaveMessage'
    "#{prefix} #{user} has left the room"
  when 'TextMessage'
    "#{prefix} #{user}: #{body}"
  when 'UploadMessage'
    "#{prefix} #{user} uploaded '#{body}'"
  when 'PasteMessage'
    "#{prefix} #{user} pasted:\n#{body}"
  when 'TopicChangeMessage'
    "#{prefix} #{user} changed the topic to '#{body}'"
  when 'ConferenceCreatedMessage'
    "#{prefix} #{user} created conference #{body}"
  when 'AllowGuestsMessage'
    "#{prefix} #{user} opened the room to guests"
  when 'DisallowGuestsMessage'
    "#{prefix} #{user} closed the room to guests"
  when 'IdleMessage'
    "#{prefix} #{user} went idle"
  when 'UnidleMessage'
    "#{prefix} #{user} became active"
  when 'TweetMessage'
    "#{prefix} #{user} tweeted #{body}"
  when 'AdvertisementMessage'
    ""
  else
    "****Unknown Message Type: #{type} - '#{body}'"
  end
end

def zero_pad(number)
  if number < 10
    "0" + number.to_s
  else
    number.to_s
  end
end

def directory(room, date)
  "campfire/#{room}/#{date.year}/#{zero_pad(date.mon)}/#{zero_pad(date.day)}"
end

doc = Nokogiri::XML get('/rooms.xml').body
doc.css('room').each do |room_xml|
  room = room_xml.css('name').text
  id   = room_xml.css('id').text  
  date = start_date

  while date <= end_date
    print "#{room}: #{date.year}/#{date.mon}/#{date.mday}..."
    transcript = Nokogiri::XML get("/room/#{id}/transcript/#{date.year}/#{date.mon}/#{date.mday}.xml").body  
    messages = transcript.css('message')

    if messages.length > 0
      puts "found transcript"
      
      FileUtils.mkdir_p directory(room, date)
      output = "#{room_xml.css('name').text} Transcript\n"
    
      messages.each do |message|
        next if message.css('type').text == 'TimestampMessage'
    
        output << message_to_string(message) << "\n"

        if message.css('type').text == "UploadMessage"
          # We get the HTML page because the XML doesn't contain the URL for the uploaded file :(
          html_transcript = Nokogiri::XML get("/room/#{id}/transcript/#{date.year}/#{date.mon}/#{date.mday}")
          file_name = "#{message.css('body').text}"
          # I am sure there's a better way than cycling through all the hyperlinks
          html_transcript.css('a').each do |link|
            if link.text == file_name
              open("#{directory(room, date)}/#{link.text}", "wb") { |file|
                file.write(get(link.attr("href")))
               }
               # We break because there are two links with the same file on the HTML page
               break
            end
          end
        end
      end
      
      open("#{directory(room, date)}/transcript.xml", 'w') do |f|
        f.puts transcript
      end

      open("#{directory(room, date)}/transcript.txt", 'w') do |f|
        f.puts output
      end
    else
      puts "skipping"
    end
      
    date = date.next
    
    sleep(1.0/10.0)
  end
end
