#require 'spec_helper'
require 'campfire_export'
require 'tzinfo'

module CampfireExport
  describe Account do
    before(:each) do
      @subdomain = "test-subdomain"
      @api_token = "test-apikey"
      @account = Account.new(@subdomain, @api_token)

      @good_timezone = '<select id="account_time_zone_id">' +
          '<option selected="selected" value="America/Los_Angeles">' +
          '</option></select>'
      @bad_timezone = @good_timezone.gsub('America/Los_Angeles', 
                                          'No Such Timezone')
      @timezone_html = stub("timezone HTML block")
      @timezone_html.stub(:body).and_return(@good_timezone)
    end
      
    context "when it is created" do
      it "sets up the account config variables" do
        Account.subdomain.should equal(@subdomain)
        Account.api_token.should equal(@api_token)
        Account.base_url.should == "https://#{@subdomain}.campfirenow.com"
      end
    end
    
    context "when timezone is loaded" do
      it "determines the user's timezone" do
        @account.should_receive(:get).with("/account/settings"
          ).and_return(@timezone_html)
        @account.instance_eval{ load_timezone }
        Account.timezone.to_s.should == "America - Los Angeles"
      end
      
      it "logs an error if it gets a bad time zone identifier" do
        @timezone_html.stub(:body).and_return(@bad_timezone)
        @account.stub(:get).with("/account/settings"
          ).and_return(@timezone_html)
        @account.should_receive(:log).with(:error, /couldn\'t find timezone/, 
          instance_of(TZInfo::InvalidTimezoneIdentifier))
        @account.instance_eval{ load_timezone }
        Account.timezone.to_s.should == "Etc - GMT"
      end
      
      it "logs an error if it can't get the account settings at all" do
        @account.stub(:get).with("/account/settings"
          ).and_raise(CampfireExport::Exception.new("/account/settings", 
            "Not Found", 404))
        @account.should_receive(:log).with(:error, /couldn\'t find timezone/, 
          instance_of(CampfireExport::Exception))
        @account.instance_eval{ load_timezone }
        Account.timezone.to_s.should == "Etc - GMT"
      end
    end
    
    context "when export is set up" do
      it "creates the export directory and loads the time zone" do
        FileUtils.should_receive(:mkdir_p).with("campfire/#{@subdomain}")
        @account.should_receive(:load_timezone)
        @account.instance_eval{ setup_export }
      end
    end
    
    context "when export is called" do
      it "runs export for each room" do
        @account.should_receive(:setup_export)
        room_xml = "<rooms><room>1</room><room>2</room><room>3</room></rooms>"
        room_doc = mock("room doc")
        room_doc.should_receive(:body).and_return(room_xml)
        @account.should_receive(:get).with('/rooms.xml').and_return(room_doc)
        room = mock("room")
        Room.should_receive(:new).exactly(3).times.and_return(room)
        room.should_receive(:export).with(nil, nil).exactly(3).times
        @account.export
      end

      it "logs an error if it can't get the room list" do
        @account.stub(:get).with('/rooms.xml'
          ).and_raise(CampfireExport::Exception.new('/rooms.xml', 
            "Not Found", 404))
        @account.should_receive(:log).with(:error, "room list download failed", 
          instance_of(CampfireExport::Exception))
        @account.stub(:setup_export)
        @account.export
      end
    end
  end
end
