# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class EventSerializersTest < Api::SerializerTestCase
  fixtures do
    @user = create(:user)
  end

  context "#stratocaster_event_hash" do
    test "gets avatar url" do
      event = Stratocaster::Event.new
      event.sender = @user
      event_hash = stratocaster_event(event)
      refute_nil actor_hash = event_hash["actor"]
      assert_equal "#{GitHub.alambic_avatar_url}/u/#{@user.id}?", actor_hash["avatar_url"]
    end
  end
end
