require 'campfire_export'
require 'campfire_export/timezone'

require 'nokogiri'

module CampfireExport  
  describe Message do
    include TimeZone
    
    before :each do
      @messages = Nokogiri::XML  <<XML
<messages>
  <message>
    <created-at type="datetime">2012-05-11T17:45:00Z</created-at>
    <id type="integer">111</id>
    <room-id type="integer">222</room-id>
    <user-id type="integer" nil="true"/>
    <body nil="true"/>
    <type>TimestampMessage</type>
  </message>
  <message>
    <created-at type="datetime">2012-05-11T17:47:20Z</created-at>
    <id type="integer">333</id>
    <room-id type="integer">222</room-id>
    <user-id type="integer">555</user-id>
    <body>This is a tweet</body>
    <type>TweetMessage</type>
    <tweet>
      <id>20100487385931234</id>
      <message>This is a tweet</message>
      <author_username>twitter_user</author_username>
      <author_avatar_url>avatar.jpg</author_avatar_url>
    </tweet>
  </message>
  <message>
    <created-at type="datetime">2012-05-11T17:47:23Z</created-at>
    <id type="integer">666</id>
    <room-id type="integer">222</room-id>
    <user-id type="integer">555</user-id>
    <body>Regular message</body>
    <type>TextMessage</type>
  </message>
</messages>
XML
      Account.timezone = find_tzinfo("America/Los_Angeles")
    end
    
    context "when it is created" do
      it "sets up basic properties" do
        message = Message.new(@messages.xpath('/messages/message[3]')[0], nil, nil)
        message.body.should == "Regular message"
        message.id.should   == "666"
        message.timestamp.should == "10:47 AM"
      end

      it "handles tweets correctly" do
        message = Message.new(@messages.xpath('/messages/message[2]'), nil, nil)
        message.body.should == "This is a tweet"
        message.id.should   == "333"
      end
    end
  end
end
