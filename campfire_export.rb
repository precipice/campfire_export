require 'rubygems'
require 'time'
require 'fileutils'
require 'httparty'
require 'nokogiri'

APIToken  = 'your-api-token-goes-here'
APIServer = 'http://sample.campfirenow.com'

def get(path, params = {})
  HTTParty.get "#{APIServer}#{path}",
    :query      => params,
    :basic_auth => {:username => APIToken, :password => 'X'}
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
  else
    raise "Unknown Message Type: #{type} - '#{body}'"
  end
end

def file_name(date)
  file_name = date.year.to_s
  file_name << '-'
  file_name << '0' if date.mon < 10
  file_name << date.mon.to_s
  file_name << '-'
  file_name << '0' if date.mday < 10
  file_name << date.mday.to_s
  file_name + '.txt'
end

doc = Nokogiri::XML get('/rooms.xml').body
doc.css('room').each do |room_xml|
  puts room_xml.css('name').text
  id = room_xml.css('id').text
  
  FileUtils.mkdir_p("campfire/#{id}")
  
  date = Date.civil 2010, 8, 31
  # date = Date.civil 2011, 1, 1
  
  while date < Date.today
    puts "#{date.year} #{date.mon} #{date.mday}"
    transcript = Nokogiri::XML get("/room/#{id}/transcript/#{date.year}/#{date.mon}/#{date.mday}.xml").body
    
    output = "#{room_xml.css('name').text} Transcript\n"
    
    transcript.css('message').each do |message|
      next if message.css('type').text == 'TimestampMessage'
      
      output << message_to_string(message) << "\n"
    end
    
    open("campfire/#{id}/#{file_name date}", 'w') do |f|
      f.puts output
    end
    
    date = date.next
  end
end
