# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::SendEmailToEloquaJobTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    GitHub::Logger.setup(GitHub::Config::Logging::Destination::NULL)
  end

  context "performs" do
    test "moves to the other table" do
      post_request = stub_request(:post, "https://s88570519.t.eloqua.com/e/f2?elqFormName=UntitledForm-1654030645645&elqSiteID=88570519")
      uri = "https://s88570519.t.eloqua.com/e/f2?elqFormName=UntitledForm-1654030645645&elqSiteID=88570519"
      user = create(:credit_card_user, :verified, :with_trade_screening_record)
      eloqua_args = { uri: uri, email: user.email }

      Copilot::SendEmailToEloquaJob.perform_now(eloqua_args)
      assert_requested post_request
    end
  end
end if GitHub.copilot_enabled?
