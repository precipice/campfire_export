require 'campfire_export'
require 'tzinfo'

module CampfireExport
  describe Account do
    before(:each) do
      @subdomain = "test-subdomain"
      @api_token = "test-apikey"
      @account   = Account.new(@subdomain, @api_token)
      
      @good_timezone = '<select id="account_time_zone_id">' +
          '<option selected="selected" value="America/Los_Angeles">' +
          '</option></select>'
      @bad_timezone  = @good_timezone.gsub('America/Los_Angeles', 
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
        @account.find_timezone
        Account.timezone.to_s.should == "America - Los Angeles"        
      end
      
      it "raises an error if it gets a bad time zone identifier" do
        @timezone_html.stub(:body).and_return(@bad_timezone)
        @account.stub(:get).with("/account/settings"
          ).and_return(@timezone_html)
        expect {
          @account.find_timezone
        }.to raise_error(TZInfo::InvalidTimezoneIdentifier)
      end
      
      it "raises an error if it can't get the account settings at all" do
        @account.stub(:get).with("/account/settings"
          ).and_raise(CampfireExport::Exception.new("/account/settings", 
            "Not Found", 404))
        expect {
          @account.find_timezone
        }.to raise_error(CampfireExport::Exception)
      end
    end
        
    context "when rooms are requested" do
      it "returns an array of rooms" do
        room_xml = "<rooms><room>1</room><room>2</room><room>3</room></rooms>"
        room_doc = mock("room doc")
        room_doc.should_receive(:body).and_return(room_xml)
        @account.should_receive(:get).with('/rooms.xml').and_return(room_doc)
        room = mock("room")
        Room.should_receive(:new).exactly(3).times.and_return(room)
        @account.rooms.should have(3).items
      end

      it "raises an error if it can't get the room list" do
        @account.stub(:get).with('/rooms.xml'
          ).and_raise(CampfireExport::Exception.new('/rooms.xml', 
            "Not Found", 404))
        expect {
          @account.rooms
        }.to raise_error(CampfireExport::Exception)
      end
    end
  end
end
