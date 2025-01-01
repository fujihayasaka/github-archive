# typed: true
# frozen_string_literal: true

require "test_helper"

class UserPermissionsDependencyTest < GitHub::TestCase
  test "cannot have granular permissions" do
    user = create(:user)
    refute_predicate user, :can_have_granular_permissions?
  end

  test "cannot have granular user permissions" do
    user = create(:user)
    refute_predicate user, :can_have_granular_user_permissions?
  end
end
