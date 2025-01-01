# typed: true
# frozen_string_literal: true

require "test_helper"

class User::IssueTypeDependencyTest < GitHub::TestCase
  test "returns false for issue types being enabled" do
    user = create(:user)

    refute_predicate user, :issue_types_enabled?
  end
end
