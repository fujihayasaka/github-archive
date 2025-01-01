# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotContentExclusionInstrumenterTest < GitHub::TestCase
  include CopilotTestHelper

  context "organization destroy" do
    test "queues the job" do
      rules = create(:copilot_content_exclusion_configuration, :organization)
      org_id = rules.organization_id

      Copilot::ContentExclusion::OrganizationJob.expects(:perform_later).once.with do |args|
        assert_equal :organization_destroyed, args[:action]
        assert_equal org_id, args[:organization_id]
      end

      ::Organization.find(org_id).destroy!
    end
  end
end if GitHub.copilot_enabled?
