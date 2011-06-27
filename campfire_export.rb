#!/usr/bin/env ruby

# Portions copyright 2011 Marc Hedlund <marc@precipice.org>.
# Adapted from https://gist.github.com/821553 and ancestors.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# campfire_export.rb -- export Campfire transcripts and uploaded files.
#
# Since Campfire (www.campfirenow.com) doesn't provide an export feature,
# this script implements one via the Campfire API.
#
# Configure the script below with your Campfire account details, or it will
# not run.

require 'rubygems'

require 'cgi'
require 'fileutils'
require 'find'
require 'httparty'
require 'nokogiri'
require 'time'
require 'yaml'

CONFIG = YAML.load_file("#{ENV['HOME']}/.campfire_config.yaml")

# FIXME: Quick hack to avoid putting these in an object, where they belong.
API_TOKEN  = CONFIG['api_token']
SUBDOMAIN  = CONFIG['subdomain']
BASE_URL   = "https://#{SUBDOMAIN}.campfirenow.com"
START_DATE = Date.parse(CONFIG['start_date'])
END_DATE   = Date.parse(CONFIG['end_date'])

module Campfire
  class ExportException < StandardError
    attr_accessor :resource, :message, :code
    def initialize(resource, message, code)
      @resource = resource
      @message = message
      @code = code
    end

    def to_s
      "<#{resource}>: #{code} #{message}"
    end
  end

  class Message
    attr_accessor :id, :room_id, :body, :type, :user, :timestamp, :upload

    def initialize(message)
      @id = message.css('id').text
      @room_id = message.css('room-id').text
      @body = message.css('body').text
      @type = message.css('type').text

      # FIXME: I imagine this needs to account for time zone.
      time = Time.parse message.css('created-at').text
      @timestamp = time.strftime '[%H:%M:%S]'

      no_user = ['TimestampMessage', 'SystemMessage', 'AdvertisementMessage']
      unless no_user.include?(@type)
        begin
          @user = username(message.css('user-id').text)
        rescue Campfire::ExportException
          @user = "[unknown user]"
        end
      end
            
      @upload = Campfire::Upload.new(self) if is_upload?
    end

    def username(id)
      @@usernames     ||= {}
      @@usernames[id] ||= begin
        doc = Nokogiri::XML get("/users/#{id}.xml").body
        doc.css('name').text
      end
    end

    def is_upload?
      @type == 'UploadMessage'
    end

    def indent(string, count)
      (' ' * count) + string.gsub(/(\n+)/) { $1 + (' ' * count) }
    end

    def to_s
      case type
      when 'EnterMessage'
        "#{timestamp} #{user} has entered the room"
      when 'KickMessage', 'LeaveMessage'
        "#{timestamp} #{user} has left the room"
      when 'TextMessage'
        "#{timestamp} #{user}: #{body}"
      when 'UploadMessage'
        "#{timestamp} #{user} uploaded: #{body}"
      when 'PasteMessage'
        "#{timestamp} #{user} pasted:\n#{indent(body, 2)}"
      when 'TopicChangeMessage'
        "#{timestamp} #{user} changed the topic to: #{body}"
      when 'ConferenceCreatedMessage'
        "#{timestamp} #{user} created conference: #{body}"
      when 'AllowGuestsMessage'
        "#{timestamp} #{user} opened the room to guests"
      when 'DisallowGuestsMessage'
        "#{timestamp} #{user} closed the room to guests"
      when 'LockMessage'
        "#{timestamp} #{user} locked the room"
      when 'UnlockMessage'
        "#{timestamp} #{user} unlocked the room"
      when 'IdleMessage'
        "#{timestamp} #{user} became idle"
      when 'UnidleMessage'
        "#{timestamp} #{user} became active"
      when 'TweetMessage'
        "#{timestamp} #{user} tweeted: #{body}"
      when 'SoundMessage'
        "#{timestamp} #{user} played a sound: #{body}"
      when 'TimestampMessage'
        ""
      when 'SystemMessage'
        ""
      when 'AdvertisementMessage'
        ""
      else
        log_error("unknown message type: #{type} - '#{body}'")
        ""
      end
    end
  end
  
  class Upload
    attr_accessor :message, :id, :filename, :content
    attr_reader :exception
    
    def initialize(message)
      @message = message
      @deleted = false
      
      begin
        # Get the upload object corresponding to this message.
        upload_path = "/room/#{message.room_id}/messages/#{message.id}/upload.xml"
        upload = Nokogiri::XML get(upload_path).body

        # Get the upload itself and export it.
        @id = upload.css('id').text
        @filename = upload.css('name').text
        
        escaped_name = CGI.escape(filename)
        content_path = "/room/#{message.room_id}/uploads/#{@id}/#{escaped_name}"
        @content = get(content_path)
      rescue Campfire::ExportException => e
        if e.code == 404
          # If the upload 404s, that should mean it was subsequently deleted.
          @deleted = true
        else
          @exception = e
        end
      rescue => e
        @exception = e
      end
    end
    
    def qualified_filename
      "#{id}-#{filename}"
    end
    
    def deleted?
      @deleted
    end
    
    def download_error?
      exception != nil
    end
  end
end

def log_error(message)
  puts "*** Error: #{message}"
  open("campfire/export_errors.txt", 'a') do |log|
    log.write "#{message}\n"
  end
end

def api_url(path)
  "#{BASE_URL}#{path}"
end

def get(path, params = {})
  url = api_url(path)
  response = HTTParty.get(url, :query => params,
    :basic_auth => {:username => API_TOKEN, :password => 'X'})

  if response.code >= 400
    raise Campfire::ExportException.new(url, response.message, response.code)
  end
  response
end

def export(content, directory, filename, mode='w')
  if File.exists?("#{directory}/#{filename}")
    # FIXME: keep a count of these somehow.
    log_error("export of #{directory}/#{filename} failed:\n" +
              "file already exists!\n")
  else
    open("#{directory}/#{filename}", mode) do |file|
      begin
        file.write content
      rescue => e
        log_error("export of #{directory}/#{filename} failed:\n" +
                  "#{e.backtrace.join("\n")}\n")
      end
    end
  end
end

def export_uploads(messages, export_dir)
  messages.each do |message|
    if message.is_upload?
      upload = message.upload
      print "    #{upload.qualified_filename} ... "
      export(upload.content, export_dir, upload.qualified_filename, 'wb')
      
      if upload.deleted?
        puts "deleted"
      elsif upload.download_error?
        log_error("export of #{export_dir}/#{upload.filename} failed:\n" +
          "#{upload.exception.backtrace.join("\n")}")
      else
        puts "ok"
      end
    end
  end
end

def zero_pad(number)
  "%02d" % number
end

def directory_for(room, date)
  "campfire/#{SUBDOMAIN}/#{room}/#{date.year}/" +
    "#{zero_pad(date.mon)}/#{zero_pad(date.day)}"
end

def plaintext_transcript(messages, room, date)
  plaintext = "#{room}: #{date.year}-#{date.mon}-#{date.mday}\n\n"
  messages.each do |message|
    # FIXME: this is ugly.
    plaintext_message = message.to_s
    plaintext << plaintext_message << "\n" if plaintext_message.length > 0
  end
  plaintext
end

def export_day(room, id, date)
  export_dir = directory_for(room, date)
  print "#{export_dir} ... "

  begin
    transcript_path = "/room/#{id}/transcript/#{date.year}/" +
                      "#{date.mon}/#{date.mday}"
    transcript_xml = Nokogiri::XML get("#{transcript_path}.xml").body
    messages = transcript_xml.css('message').map do |message|
      Campfire::Message.new(message)
    end

    # Only export transcripts that contain at least one message.
    if messages.length > 0
      puts "exporting transcripts"
      FileUtils.mkdir_p export_dir

      export(transcript_xml, export_dir, 'transcript.xml')
      plaintext = plaintext_transcript(messages, room, date)
      export(plaintext, export_dir, 'transcript.txt')
      export_uploads(messages, export_dir)

      begin
        transcript_html = get(transcript_path)
        export(transcript_html, export_dir, 'transcript.html')
      rescue Campfire::ExportException => e
        log_error("HTML transcript download for #{export_dir} failed: #{e}")
      end
    else
      puts "no messages"
    end
  rescue Campfire::ExportException => e
    log_error("transcript download for #{export_dir} failed: #{e}")
  end
end

def verify_export(export_directory, expected_transcripts, expected_uploads)
  actual_xml = 0
  actual_html = 0
  actual_plaintext = 0
  actual_uploads = 0

  Find.find(export_directory) do |path|
    if FileTest.file?(path)
      filename = File.basename(path)
      if filename == 'transcript.xml'
        actual_xml += 1
      elsif filename == 'transcript.html'
        actual_html += 1
      elsif filename == 'transcript.txt'
        actual_plaintext += 1
      elsif filename == 'export_errors.txt'
        next
      else
        actual_uploads += 1
      end
    end
  end

  if actual_xml != expected_transcripts
    log_error("Expected #{expected_transcripts} XML transcripts, " +
              "but only found #{actual_xml}!")
  end

  if actual_html != expected_transcripts
    log_error("Expected #{expected_transcripts} HTML transcripts, " +
              "but only found #{actual_html}!")
  end

  if actual_plaintext != expected_transcripts
    log_error("Expected #{expected_transcripts} plaintext transcripts, " +
              "but only found #{actual_plaintext}!")
  end

  if actual_uploads != expected_uploads
    log_error("Expected #{expected_uploads} uploads, " +
              "but only found #{actual_uploads}!")
  end
end

begin
  # FIXME: run export stats a different way.
  # @transcripts_found     = 0
  # @upload_messages_found = 0
  # @deleted_uploads       = 0
  # @filename_mismatches   = 0
  # @existing_files        = 0

  doc = Nokogiri::XML get('/rooms.xml').body
  doc.css('room').each do |room_xml|
    room = room_xml.css('name').text
    id   = room_xml.css('id').text
    date = START_DATE

    while date <= END_DATE
      export_day(room, id, date)
      date = date.next

      # Ensure that we stay well below the 37signals API limits.
      sleep(1.0/10.0)
    end
  end

  # net_uploads = @upload_messages_found - @deleted_uploads
  # puts "Exported #{@transcripts_found} transcript(s) " +
  #      "and #{net_uploads} uploaded file(s)."
  # verify_export('campfire', @transcripts_found, net_uploads)
  # 
  # if @filename_mismatches > 0
  #   log_error("Encountered #{@filename_mismatches} filename mismatch(es).")
  # end
  # 
  # if @existing_files > 0
  #   log_error("Encountered #{@existing_files} existing file(s).")
  # end
rescue Campfire::ExportException => e
  log_error("room list download failed: #{e}")
end
