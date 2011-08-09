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

require 'rubygems'

require 'campfire_export/timezone'

require 'cgi'
require 'fileutils'
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

    # Requires that room and date be defined in the calling object.
    def export_dir
      "campfire/#{Account.subdomain}/#{room.name}/" +
        "#{date.year}/#{zero_pad(date.mon)}/#{zero_pad(date.day)}"
    end

    # Requires that room_name and date be defined in the calling object.    
    def export_file(content, filename, mode='w')
      # Check to make sure we're writing into the target directory tree.
      true_path = File.expand_path(File.join(export_dir, filename))
      
      unless true_path.start_with?(File.expand_path(export_dir))
        raise CampfireExport::Exception.new("#{export_dir}/#{filename}",
          "can't export file to a directory higher than target directory; " +
          "expected: #{File.expand_path(export_dir)}, actual: #{true_path}.")
      end
      
      if File.exists?("#{export_dir}/#{filename}")
        log(:error, "#{export_dir}/#{filename} failed: file already exists")
      else
        open("#{export_dir}/#{filename}", mode) do |file|
          file.write content
        end
      end
    end
    
    def verify_export(filename, expected_size)
      full_path = "#{export_dir}/#{filename}"
      unless File.exists?(full_path)
        raise CampfireExport::Exception.new(full_path, 
          "file should have been exported but did not make it to disk")
      end
      unless File.size(full_path) == expected_size
        raise CampfireExport::Exception.new(full_path, 
          "exported file exists but is not the right size " +
          "(expected: #{expected_size}, actual: #{File.size(full_path)})")
      end
    end
    
    def log(level, message, exception=nil)
      case level
      when :error
        short_error = ["*** Error: #{message}", exception].compact.join(": ")
        $stderr.puts short_error
        open("campfire/export_errors.txt", 'a') do |log|
          log.write short_error
          unless exception.nil?
            log.write %Q{\n\t#{exception.backtrace.join("\n\t")}}
          end
          log.write "\n"
        end
      else
        print message
        $stdout.flush
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
      "<#{resource}>: #{message}" + (code ? " (#{code})" : "")
    end
  end

  class Account
    include CampfireExport::IO
    include CampfireExport::TimeZone
    
    @subdomain = ""
    @api_token = ""
    @base_url  = ""
    @timezone  = nil
    
    class << self
      attr_accessor :subdomain, :api_token, :base_url, :timezone
    end
    
    def initialize(subdomain, api_token)
      Account.subdomain = subdomain
      Account.api_token = api_token
      Account.base_url  = "https://#{subdomain}.campfirenow.com"
    end

    def find_timezone
      settings = Nokogiri::XML get('/account.xml').body
      selected_zone = settings.css('time-zone')
      Account.timezone = find_tzinfo(selected_zone.text)
    end

    def rooms
      doc = Nokogiri::XML get('/rooms.xml').body
      doc.css('room').map {|room_xml| Room.new(room_xml) }
    end
  end

  class Room
    include CampfireExport::IO
    attr_accessor :id, :name, :created_at, :last_update
    
    def initialize(room_xml)
      @id         = room_xml.css('id').text
      @name       = room_xml.css('name').text
      created_utc = DateTime.parse(room_xml.css('created-at').text)
      @created_at = Account.timezone.utc_to_local(created_utc)
    end
    
    def export(start_date=nil, end_date=nil)
      # Figure out how to do the least amount of work while still conforming
      # to the requester's boundary dates.
      find_last_update
      start_date.nil? ? date = created_at      : date = [start_date, created_at].max
      end_date.nil?   ? end_date = last_update : end_date = [end_date, last_update].min
      
      while date <= end_date
        transcript = Transcript.new(self, date)
        transcript.export

        # Ensure that we stay well below the 37signals API limits.
        sleep(1.0/10.0)
        date = date.next
      end
    end
    
    private
      def find_last_update
        begin
          last_message = Nokogiri::XML get("/room/#{id}/recent.xml?limit=1").body
          update_utc   = DateTime.parse(last_message.css('created-at').text)
          @last_update = Account.timezone.utc_to_local(update_utc)
        rescue Exception => e
          log(:error, 
              "couldn't get last update in #{room} (defaulting to today)", 
              e)
          @last_update = Time.now
        end
      end
  end

  class Transcript
    include CampfireExport::IO
    attr_accessor :room, :date, :xml, :messages
    
    def initialize(room, date)
      @room     = room
      @date     = date
    end
    
    def transcript_path
      "/room/#{room.id}/transcript/#{date.year}/#{date.mon}/#{date.mday}"
    end
    
    def export
      begin
        log(:info, "#{export_dir} ... ")
        @xml = Nokogiri::XML get("#{transcript_path}.xml").body      
      rescue Exception => e
        log(:error, "transcript export for #{export_dir} failed", e)
      else
        @messages = xml.css('message').map do |message|
          CampfireExport::Message.new(message, room, date)
        end
      
        # Only export transcripts that contain at least one message.
        if messages.length > 0
          log(:info, "exporting transcripts\n")
          begin
            FileUtils.mkdir_p export_dir
          rescue Exception => e
            log(:error, "Unable to create #{export_dir}", e)
          else
            export_xml
            export_plaintext
            export_html
            export_uploads
          end
        else
          log(:info, "no messages\n")
        end      
      end
    end
    
    def export_xml
      begin
        export_file(xml, 'transcript.xml')
        verify_export('transcript.xml', xml.to_s.length)
      rescue Exception => e
        log(:error, "XML transcript export for #{export_dir} failed", e)
      end
    end

    def export_plaintext
      begin
        date_header = date.strftime('%A, %B %e, %Y').squeeze(" ")
        plaintext = "#{CampfireExport::Account.subdomain.upcase} CAMPFIRE\n"
        plaintext << "#{room.name}: #{date_header}\n\n"
        messages.each {|message| plaintext << message.to_s }
        export_file(plaintext, 'transcript.txt')
        verify_export('transcript.txt', plaintext.length)
      rescue Exception => e
        log(:error, "Plaintext transcript export for #{export_dir} failed", e)
      end
    end
        
    def export_html
      begin
        transcript_html = get(transcript_path)

        # Make the upload links in the transcript clickable from the exported 
        # directory layout.
        transcript_html.gsub!(%Q{href="/room/#{room.id}/uploads/},
                              %Q{href="uploads/})
        # Likewise, make the image thumbnails embeddable from the exported
        # directory layout.
        transcript_html.gsub!(%Q{src="/room/#{room.id}/thumb/},
                              %Q{src="thumbs/})
        
        export_file(transcript_html, 'transcript.html')
        verify_export('transcript.html', transcript_html.length)
      rescue Exception => e
        log(:error, "HTML transcript export for #{export_dir} failed", e)
      end
    end

    def export_uploads
      messages.each do |message|
        if message.is_upload?
          begin
            message.upload.export
          rescue Exception => e
            path = "#{message.upload.export_dir}/#{message.upload.filename}"
            log(:error, "Upload export for #{path} failed", e)
          end
        end
      end
    end    
  end
  
  class Message
    include CampfireExport::IO
    attr_accessor :id, :room, :body, :type, :user, :date, :timestamp, :upload

    def initialize(message, room, date)
      @id = message.css('id').text
      @room = room
      @date = date
      @body = message.css('body').text
      @type = message.css('type').text

      time = Time.parse message.css('created-at').text
      localtime = CampfireExport::Account.timezone.utc_to_local(time)
      @timestamp = localtime.strftime '%I:%M %p'

      no_user = ['TimestampMessage', 'SystemMessage', 'AdvertisementMessage']
      unless no_user.include?(@type)
        @user = username(message.css('user-id').text)
      end
      
      @upload = CampfireExport::Upload.new(self) if is_upload?
    end

    def username(user_id)
      @@usernames          ||= {}
      @@usernames[user_id] ||= begin
        doc = Nokogiri::XML get("/users/#{user_id}.xml").body
      rescue Exception => e
        "[unknown user]"
      else
        # Take the first name and last initial, if there is more than one name.
        name_parts = doc.css('name').text.split
        if name_parts.length > 1
          name_parts[-1] = "#{name_parts.last[0,1]}."
          name_parts.join(" ")
        else
          name_parts[0]
        end
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
        "[#{user} has entered the room]\n"
      when 'KickMessage', 'LeaveMessage'
        "[#{user} has left the room]\n"
      when 'TextMessage'
        "[#{user.rjust(12)}:] #{body}\n"
      when 'UploadMessage'
        "[#{user} uploaded: #{body}]\n"
      when 'PasteMessage'
        "[" + "#{user} pasted:]".rjust(14) + "\n#{indent(body, 16)}\n"
      when 'TopicChangeMessage'
        "[#{user} changed the topic to: #{body}]\n"
      when 'ConferenceCreatedMessage'
        "[#{user} created conference: #{body}]\n"
      when 'AllowGuestsMessage'
        "[#{user} opened the room to guests]\n"
      when 'DisallowGuestsMessage'
        "[#{user} closed the room to guests]\n"
      when 'LockMessage'
        "[#{user} locked the room]\n"
      when 'UnlockMessage'
        "[#{user} unlocked the room]\n"
      when 'IdleMessage'
        "[#{user} became idle]\n"
      when 'UnidleMessage'
        "[#{user} became active]\n"
      when 'TweetMessage'
        "[#{user} tweeted:] #{body}\n"
      when 'SoundMessage'
        "[#{user} played a sound:] #{body}\n"
      when 'TimestampMessage'
        "--- #{timestamp} ---\n"
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
    attr_accessor :message, :room, :date, :id, :filename, :content_type, :byte_size
    
    def initialize(message)
      @message = message
      @room = message.room
      @date = message.date
      @deleted = false
    end
    
    def deleted?
      @deleted
    end
    
    def is_image?
      content_type.start_with?("image/")
    end
    
    def upload_dir
      "uploads/#{id}"
    end
    
    # Image thumbnails are used to inline image uploads in HTML transcripts.
    def thumb_dir
      "thumbs/#{id}"
    end
    
    def export
      begin
        log(:info, "    #{message.body} ... ")

        # Get the upload object corresponding to this message.
        upload_path = "/room/#{room.id}/messages/#{message.id}/upload.xml"
        upload = Nokogiri::XML get(upload_path).body
        
        # Get the upload itself and export it.
        @id = upload.css('id').text
        @byte_size = upload.css('byte-size').text.to_i
        @content_type = upload.css('content-type').text
        @filename = upload.css('name').text

        export_content(upload_dir)
        export_content(thumb_dir, path_component="thumb/#{id}", verify=false) if is_image?
                
        log(:info, "ok\n")
      rescue CampfireExport::Exception => e
        if e.code == 404
          # If the upload 404s, that should mean it was subsequently deleted.
          @deleted = true
          log(:info, "deleted\n")
        else
          raise e
        end
      end
    end
    
    def export_content(content_dir, path_component=nil, verify=true)
      # If the export directory name is different than the URL path component,
      # the caller can define the path_component separately.
      path_component ||= content_dir
      
      # Write uploads to a subdirectory, using the upload ID as a directory
      # name to avoid overwriting multiple uploads of the same file within
      # the same day (for instance, if 'Picture 1.png' is uploaded twice
      # in a day, this will preserve both copies). This path pattern also
      # matches the tail of the upload path in the HTML transcript, making
      # it easier to make downloads functional from the HTML transcripts.
      content_path = "/room/#{room.id}/#{path_component}/#{CGI.escape(filename)}"        
      content = get(content_path).body
      FileUtils.mkdir_p(File.join(export_dir, content_dir))
      export_file(content, "#{content_dir}/#{filename}", 'wb')
      verify_export("#{content_dir}/#{filename}", byte_size) if verify
    end
  end
end
