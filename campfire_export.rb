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

###
# Script configuration - all options are required.

# Export start date - the first transcript you want exported.
START_DATE = Date.civil(2010, 1, 1)

# Export end date - the last transcript you want exported, inclusive.
END_DATE   = Date.civil(2010, 12, 31)

# Your Campfire API token (see "My Info" on your Campfire site).
API_TOKEN  = ''

# Your Campfire subdomain (for 'https://myco.campfirenow.com', enter 'myco').
SUBDOMAIN  = ''

# End of configuration
###

BASE_URL = "https://#{SUBDOMAIN}.campfirenow.com"

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

def username(id)
  @usernames     ||= {}
  @usernames[id] ||= begin
    doc = Nokogiri::XML get("/users/#{id}.xml").body
    doc.css('name').text
  end
end

def export(content, directory, filename, mode='w')
  if File.exists?("#{directory}/#{filename}")
    @existing_files += 1
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

def export_upload(message, directory)
  begin
    # Get the upload object corresponding to this message.
    room_id = message.css('room-id').text
    message_id = message.css('id').text
    message_body = message.css('body').text
    print "#{directory}/#{message_body} ... "
    upload_path = "/room/#{room_id}/messages/#{message_id}/upload.xml"
    upload = Nokogiri::XML get(upload_path).body

    # Get the upload itself and export it.
    upload_id = upload.css('id').text
    filename = upload.css('name').text
    full_url = upload.css('full-url').text

    if filename != message_body
      @filename_mismatches += 1
      log_error("Filename mismatch for room #{room_id}, " +
                "message #{message_id}, upload #{upload_id},\n" +
                "in #{directory}:\n" +
                "  Message body: #{message_body}\n" +
                "  Filename:     #{filename}")

      begin
        # Check the mismatched names against a pattern to pin down the bug.
        regex = Regexp.new('^(.*?)\-[^\-.]+(\.\w+)$', true)
        if regex.match(message_body).to_a.slice(1..-1).join('') == filename
          log_error("Test pattern matches.\n")
        else
          log_error("*** Test pattern does NOT match. ***\n")
        end
      rescue => e
        log_error("Test pattern failed to run.\n")
      end
    end

    escaped_name = CGI.escape(filename)
    content_path = "/room/#{room_id}/uploads/#{upload_id}/#{escaped_name}"
    content = get(content_path)

    puts "exporting"
    # NOTE: using the message_body instead of the filename to save exported
    # files, because of a bug in filenames causing name collisions. See the
    # "filename mismatch" warning above.
    export(content, directory, message_body, 'wb')
  rescue Campfire::ExportException => e
    if e.code == 404
      # If the upload 404s, that should mean it was subsequently deleted.
      @deleted_uploads += 1
      puts "***deleted***"
    else
      log_error("download of #{directory}/#{message_body} failed:\n" +
                "#{e.backtrace.join("\n")}\n")
    end
  rescue => e
    log_error("exception in export of #{directory}/#{message_body}:\n" +
              "#{e.backtrace.join("\n")}\n")
  end
end

def export_uploads(messages, export_dir)
  messages.each do |message|
    if message.css('type').text == "UploadMessage"
      @upload_messages_found += 1
      export_upload(message, export_dir)
    end
  end
end

def indent(string, count)
  (' ' * count) + string.gsub(/(\n+)/) { $1 + (' ' * count) }
end

def message_to_string(message)
  type = message.css('type').text
  if type != 'TimestampMessage'
    begin
      user = username(message.css('user-id').text)
    rescue Campfire::ExportException
      user = "[unknown user]"
    end
  end
  
  body = message.css('body').text

  # FIXME: I imagine this needs to account for time zone.
  time = Time.parse message.css('created-at').text
  timestamp = time.strftime '[%H:%M:%S]'
  
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
    "#{timestamp} #{user} pasted:\n#{indent(body, 4)}"
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
    message_text = message_to_string(message)
    plaintext << message_text << "\n" if message_text.length > 0
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
    messages = transcript_xml.css('message')

    # Only export transcripts that contain at least one message.
    if messages.length > 0
      @transcripts_found += 1
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
  @transcripts_found     = 0
  @upload_messages_found = 0
  @deleted_uploads       = 0
  @filename_mismatches   = 0
  @existing_files        = 0

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

  net_uploads = @upload_messages_found - @deleted_uploads
  puts "Exported #{@transcripts_found} transcript(s) " +
       "and #{net_uploads} uploaded file(s)."
  verify_export('campfire', @transcripts_found, net_uploads)

  if @filename_mismatches > 0
    log_error("Encountered #{@filename_mismatches} filename mismatch(es).")
  end

  if @existing_files > 0
    log_error("Encountered #{@existing_files} existing file(s).")
  end
rescue Campfire::ExportException => e
  log_error("room list download failed: #{e}")
end
