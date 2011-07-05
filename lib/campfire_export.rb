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

module CampfireExport
  module IO
    def api_url(path)
      "#{CampfireExport::Account.base_url}#{path}"
    end

    def get(path, params = {})
      url = api_url(path)
      response = HTTParty.get(url, :query => params, :basic_auth => 
        {:username => CampfireExport::Account.api_token, :password => 'X'})

      if response.code >= 400
        raise CampfireExport::Exception.new(url, response.message, response.code)
      end
      response
    end
    
    def zero_pad(number)
      "%02d" % number
    end

    def export_dir
      "campfire/#{CampfireExport::Account.subdomain}/#{room}/#{date.year}/" +
        "#{zero_pad(date.mon)}/#{zero_pad(date.day)}"
    end
    
    def export_file(content, directory, filename, mode='w')
      if File.exists?("#{directory}/#{filename}")
        log(:error, "#{directory}/#{filename} failed: file already exists.")
      else
        open("#{directory}/#{filename}", mode) do |file|
          begin
            file.write content
          rescue => e
            log(:error, "#{directory}/#{filename} failed: " +
              "#{e.backtrace.join("\n")}")
          end
        end
      end
    end
    
    def log(level, message)
      case level
      when :error
        puts "*** Error: #{message}"
        open("campfire/export_errors.txt", 'a') do |log|
          log.write "#{message}\n"
        end
      else
        puts message
      end
    end
  end
  
  class Exception < StandardError
    attr_accessor :resource, :message, :code
    def initialize(resource, message, code=nil)
      @resource = resource
      @message = message
      @code = code
    end

    def to_s
      "<#{resource}>: #{message}" + (" (#{code})" if code)
    end
  end

  class Account
    include CampfireExport::IO
    
    @subdomain = ""
    @api_token = ""
    @base_url  = ""
    
    class << self
      attr_accessor :subdomain, :api_token, :base_url
    end
    
    def initialize(subdomain, api_token)
      CampfireExport::Account.subdomain = subdomain
      CampfireExport::Account.api_token = api_token
      CampfireExport::Account.base_url  = "https://#{subdomain}.campfirenow.com"
    end
    
    def export(start_date, end_date)
      begin
        doc = Nokogiri::XML get('/rooms.xml').body
        doc.css('room').each do |room_xml|
          room = CampfireExport::Room.new(room_xml)
          room.export(start_date, end_date)
        end
      rescue CampfireExport::Exception => e
        log(:error, "room list download failed: #{e}")
      end
    end
  end

  class Room
    include CampfireExport::IO
    attr_accessor :id, :room, :created_at
    
    def initialize(room)
      @id         = room.css('id').text
      @room       = room.css('name').text
      @created_at = room.css('created-at').text
    end
    
    def export(start_date, end_date)
      date = start_date

      while date <= end_date
        transcript = CampfireExport::Transcript.new(id, room, date)
        transcript.export

        # Ensure that we stay well below the 37signals API limits.
        sleep(1.0/10.0)
        date = date.next
      end
    end
  end

  class Transcript
    include CampfireExport::IO
    attr_accessor :id, :room, :date
    
    def initialize(id, room, date)
      @id = id
      @room = room
      @date = date
    end
    
    def export
      begin
        transcript_path = "/room/#{id}/transcript/#{date.year}/" +
                          "#{date.mon}/#{date.mday}"
        transcript_xml = Nokogiri::XML get("#{transcript_path}.xml").body
        messages = transcript_xml.css('message').map do |message|
          CampfireExport::Message.new(message)
        end

        # Only export transcripts that contain at least one message.
        if messages.length > 0
          log(:info, "exporting transcripts")
          FileUtils.mkdir_p directory

          export(transcript_xml, directory, 'transcript.xml')
          plaintext = plaintext_transcript(messages, room, date)
          export(plaintext, directory, 'transcript.txt')
          export_uploads(messages, directory)

          begin
            transcript_html = get(transcript_path)
            export(transcript_html, directory, 'transcript.html')
          rescue CampfireExport::Exception => e
            log(:error, "HTML transcript download for #{export_dir} failed: #{e}")
          end
        else
          log(:info, "no messages")
        end
      rescue CampfireExport::Exception => e
        log(:error, "transcript download for #{export_dir} failed: #{e}")
      end
    end
    
    def plaintext
      text = "#{room}: #{date.year}-#{date.mon}-#{date.mday}\n\n"
      messages.each do |message|
        text << message.to_s
      end
      text
    end

    def export_uploads
      messages.each do |message|
        if message.is_upload?
          message.upload.export(directory)
        end
      end
    end    
  end
  
  class Message
    include CampfireExport::IO
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
        rescue CampfireExport::Exception
          @user = "[unknown user]"
        end
      end
            
      @upload = CampfireExport::Upload.new(self) if is_upload?
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
        "#{timestamp} #{user} has entered the room\n"
      when 'KickMessage', 'LeaveMessage'
        "#{timestamp} #{user} has left the room\n"
      when 'TextMessage'
        "#{timestamp} #{user}: #{body}\n"
      when 'UploadMessage'
        "#{timestamp} #{user} uploaded: #{body}\n"
      when 'PasteMessage'
        "#{timestamp} #{user} pasted:\n#{indent(body, 2)}"
      when 'TopicChangeMessage'
        "#{timestamp} #{user} changed the topic to: #{body}\n"
      when 'ConferenceCreatedMessage'
        "#{timestamp} #{user} created conference: #{body}\n"
      when 'AllowGuestsMessage'
        "#{timestamp} #{user} opened the room to guests\n"
      when 'DisallowGuestsMessage'
        "#{timestamp} #{user} closed the room to guests\n"
      when 'LockMessage'
        "#{timestamp} #{user} locked the room\n"
      when 'UnlockMessage'
        "#{timestamp} #{user} unlocked the room\n"
      when 'IdleMessage'
        "#{timestamp} #{user} became idle\n"
      when 'UnidleMessage'
        "#{timestamp} #{user} became active\n"
      when 'TweetMessage'
        "#{timestamp} #{user} tweeted: #{body}\n"
      when 'SoundMessage'
        "#{timestamp} #{user} played a sound: #{body}\n"
      when 'TimestampMessage'
        ""
      when 'SystemMessage'
        ""
      when 'AdvertisementMessage'
        ""
      else
        log(:error, "unknown message type: #{type} - '#{body}'")
        ""
      end
    end
  end
  
  class Upload
    include CampfireExport::IO
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
    
    def deleted?
      @deleted
    end
    
    def download_error?
      exception != nil
    end
    
    def export(export_dir)
      # Write uploads to a subdirectory, using the upload ID as a directory
      # name to avoid overwriting multiple uploads of the same file within
      # the same day (for instance, if 'Picture 1.png' is uploaded twice
      # in a day, this will preserve both copies). This path pattern also
      # matches the tail of the upload path in the HTML transcript, making
      # it easier to make downloads functional from the HTML transcripts.
      upload_dir = "#{export_dir}/uploads/#{id}"
      print "    uploads/#{id}/#{filename} ... "

      if download_error?
        log(:error, "export of #{export_dir}/#{filename} failed:\n" +
          "#{exception.backtrace.join("\n")}")
      elsif deleted?
        log(:info, "deleted")
      else
        FileUtils.mkdir_p "#{upload_dir}"
        export_file(content, upload_dir, filename, 'wb')
        log(:info, "ok")
      end
    end
  end
end
