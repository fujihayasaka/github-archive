# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessAuditLogEventsTest < GitHub::TestCase
  include AuditLogHelpers

  setup do
    @business = create :business
    @excluded_business = create :business

    with_es_refresh do
      @business.add_organization(create(:organization))
      @excluded_business.add_organization(create(:organization))
    end

    @business_for_multiple_actions = create :business
    with_es_refresh do
      org = create :organization
      @business_for_multiple_actions.add_organization(org)
      @business_for_multiple_actions.remove_organization(org)
    end
  end

  context "#find_audit_events" do
    test "finds audit events for the Business" do
      events = @business.find_audit_events("business.add_organization")
      assert_equal 1, events.length
    end

    test "returns empty array when no results are found" do
      events = @business.find_audit_events("foo")
      assert_empty events
    end
  end

  context "#find_audit_events_for_actions" do
    test "finds audit_events matching any of the actions passed" do
      events = @business_for_multiple_actions.find_audit_events_for_actions([
        "business.add_organization",
        "business.remove_organization"
      ])
      assert_equal 2, events.length
    end

    test "returns empty array when no results are found" do
      events = @business_for_multiple_actions.find_audit_events_for_actions(["foo"])
      assert_empty events
    end
  end
end unless GitHub.single_business_environment?
