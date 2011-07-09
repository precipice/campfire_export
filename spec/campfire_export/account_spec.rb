#require 'spec_helper'
require 'campfire_export'

module CampfireExport
  describe Account do
    describe "initialize" do
      it "sets up account configuration" do
        subdomain = "test-subdomain"
        api_token = "test-apikey"
        account = Account.new(subdomain, api_token)
        Account.subdomain.should equal(subdomain)
        Account.api_token.should equal(api_token)
        Account.base_url.should == "https://test-subdomain.campfirenow.com"
      end
      
      it "creates the export directory"
      it "determines the user's time zone"
    end
  end
end
