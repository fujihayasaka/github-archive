# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsRateLimitContextTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @context = Stafftools::RateLimitContext.new(@user)
  end

  context "#initialization" do
    test "assigns the user" do
      assert_equal @user, @context.current_user
    end
  end
  context "#responses" do
    test "returns nil for stubbed accessors" do
      %w(current_app current_integration_installation remote_ip)
        .each do |accessor|
        assert_nil @context.send(accessor)
      end
    end
  end
end
