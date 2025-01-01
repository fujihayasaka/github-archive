# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::CopilotWorkspaceBillingMessageHandlerResultTest < GitHub::TestCase
  context "#publish" do
    test "it proxies the payload through to a background job" do
      payload = { hi: "there" }
      result = Codespaces::CopilotWorkspaceBillingMessageHandlerResult.new(payload)
      result.publish
      assert_enqueued_with(job: Codespaces::CreateUsageRecordJob, args: [payload])
    end
  end
end unless GitHub.enterprise?
