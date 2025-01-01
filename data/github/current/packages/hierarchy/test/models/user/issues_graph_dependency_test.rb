# typed: true
# frozen_string_literal: true

require "test_helper"

class User::IssuesGraphDependencyTest < GitHub::TestCase
  fixtures do
    @hierarchy_user = create(:user)
  end

  context "to_hierarchy_model" do
    test "creates a hierarchy model" do
      model = @hierarchy_user.to_hierarchy_model

      assert_equal @hierarchy_user.id, model[:id]
      assert_equal @hierarchy_user.display_login, model[:login]
      assert_equal @hierarchy_user.primary_avatar_url, model[:avatarUrl]
    end
  end
end
