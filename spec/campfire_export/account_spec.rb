#require 'spec_helper'
require 'campfire_export'
require 'tzinfo'

module CampfireExport
  describe Account do
    before(:each) do
      @subdomain = "test-subdomain"
      @api_token = "test-apikey"
      @account = Account.new(@subdomain, @api_token)
    end
      
    context "when it is created" do
      it "sets up the account config variables" do
        Account.subdomain.should equal(@subdomain)
        Account.api_token.should equal(@api_token)
        Account.base_url.should == "https://#{@subdomain}.campfirenow.com"
      end
    end
    
    context "when timezone is loaded" do
      before(:each) do
        @good_timezone = '<select id="account_time_zone_id">' +
            '<option selected="selected" value="America/Los_Angeles">' +
            '</option></select>'
        @bad_timezone = @good_timezone.gsub('America/Los_Angeles', 
                                            'No Such Timezone')
        @timezone_html = stub("timezone HTML block")
      end
      
      it "creates the export directory" do
        @timezone_html.stub(:body).and_return(@good_timezone)
        FileUtils.should_receive(:mkdir_p).with("campfire/#{@subdomain}")
        @account.stub(:get).with("/account/settings"
          ).and_return(@timezone_html)
        @account.load_timezone
      end
      
      it "determines the user's timezone" do
        @timezone_html.stub(:body).and_return(@good_timezone)
        FileUtils.stub(:mkdir_p).with("campfire/#{@subdomain}")
        @account.should_receive(:get).with("/account/settings"
          ).and_return(@timezone_html)
        @account.load_timezone
        Account.timezone.to_s.should == "America - Los Angeles"
      end
      
      it "raises an error if it gets a bad time zone identifier" do
        @timezone_html.stub(:body).and_return(@bad_timezone)
        FileUtils.stub(:mkdir_p).with("campfire/#{@subdomain}")
        @account.stub(:get).with("/account/settings"
          ).and_return(@timezone_html)
        @account.should_receive(:log).with(:error, /couldn\'t find timezone/, 
          instance_of(TZInfo::InvalidTimezoneIdentifier))
        @account.load_timezone
      end
      
      it "logs an error if it can't get the account settings at all" do
        @timezone_html.stub(:body).and_return(@good_timezone)
        FileUtils.stub(:mkdir_p).with("campfire/#{@subdomain}")
        @account.stub(:get).with("/account/settings"
          ).and_raise(CampfireExport::Exception.new("/account/settings", 
            "Not Found", 404))
        @account.should_receive(:log).with(:error, /couldn\'t find timezone/, 
          instance_of(CampfireExport::Exception))
        @account.load_timezone
      end
    end
  end
end
