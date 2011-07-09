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
        @timezone_html.stub(:body).and_return(@good_timezone)
        @account.should_receive(:get).with("/account/settings"
          ).and_return(@timezone_html)
        @account.load_timezone
        Account.timezone.to_s.should == "America - Los Angeles"
      end
      
      it "logs an error if it gets a bad time zone identifier" do
        @timezone_html.stub(:body).and_return(@bad_timezone)
        @account.stub(:get).with("/account/settings"
          ).and_return(@timezone_html)
        @account.should_receive(:log).with(:error, /couldn\'t find timezone/, 
          instance_of(TZInfo::InvalidTimezoneIdentifier))
        @account.load_timezone
        Account.timezone.to_s.should == "Etc - GMT"
      end
      
      it "logs an error if it can't get the account settings at all" do
        @timezone_html.stub(:body).and_return(@good_timezone)
        @account.stub(:get).with("/account/settings"
          ).and_raise(CampfireExport::Exception.new("/account/settings", 
            "Not Found", 404))
        @account.should_receive(:log).with(:error, /couldn\'t find timezone/, 
          instance_of(CampfireExport::Exception))
        @account.load_timezone
        Account.timezone.to_s.should == "Etc - GMT"
      end
    end
    
    context "when export is started" do
      it "creates the export directory"
          # room_list = mock("room list")
          # room_xml = mock("room xml")
          # room = mock("room")
          # FileUtils.should_receive(:mkdir_p).with("campfire/#{@subdomain}")
          # @account.stub(:load_timezone)
          # @account.stub(:get).with('/rooms.xml').and_return(room_list)
          # room_list.stub(:css, :each).and_yield(room_xml)
          # Room.stub(:new).with(room_xml).and_return(room)
          # room.stub(:export).with(nil, nil)
          # @account.export
      
      it "loads the timezone"
      it "runs export for each room"
      it "logs an error if it can't get the room list"
    end
  end
end
