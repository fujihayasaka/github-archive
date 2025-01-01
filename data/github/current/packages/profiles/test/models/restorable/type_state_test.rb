# typed: true
# frozen_string_literal: true

require "test_helper"

class RestorableTypeStateTest < GitHub::TestCase
  test ".states numbering does not change" do
    # Update this test with new states when they are added. NEVER reorder them.
    expected_state_values = {
      saved: 0,
      restoring: 1,
      restored: 2,
    }.with_indifferent_access
    assert_equal expected_state_values, Restorable::TypeState.states
  end

  test "TYPES numbering does not change" do
    # Update this test when new types are added. NEVER reorder them.
    expected_types = {
      restorable_memberships: 0,
      restorable_repositories: 1,
      restorable_repository_stars: 2,
      restorable_watched_repositories: 3,
      restorable_issue_assignments: 4,
      restorable_custom_email_routings: 5,
    }.with_indifferent_access
    assert_equal expected_types, Restorable::TypeState.restorable_types
  end
end
