# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotOrganizationsBusinessTest < GitHub::TestCase
  context "#copilot_business" do
    test "no business" do
      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)
      assert_nil copilot_org.copilot_business
    end

    test "with business" do
      org = create(:enterprise_linked_organization)
      copilot_org = Copilot::Organization.new(org)
      assert_equal org.business,
        copilot_org.copilot_business&.business_object
    end
  end
end if GitHub.copilot_enabled?
