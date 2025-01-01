# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Codespaces::VscodeBillingThresholdNotifierJobTest < GitHub::TestCase
  include JobTestHelper

  context "#perform" do
    test "calls the command" do
      codespace = create(:codespace)
      Codespaces::Billing::VscodeThresholdNotifier.expects(:call).with(codespace: codespace, billable_owner: codespace.billable_owner)
      Codespaces::VscodeBillingThresholdNotifierJob.perform_now(codespace: codespace, billable_owner: codespace.billable_owner)
    end
  end


end unless GitHub.enterprise?
