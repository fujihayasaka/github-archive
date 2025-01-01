# typed: true
# frozen_string_literal: true

require "test_helper"

class OnboardingTasks::AdvancedSecurity::SecurityConfigurations::AssignSecurityManagerRolesTest < GitHub::TestCase
  include HydroTestHelpers
  include UrlHelper

  fixtures do
    @owner = create(:user)
    @org = create(:organization, login: "my-hero", admin: @owner)
  end

  context "#task_link" do
    test "returns the correct path" do
      task = OnboardingTasks::AdvancedSecurity::SecurityConfigurations::AssignSecurityManagerRoles.new(
        taskable: @org,
        user: @owner
      )

      assert_equal "/organizations/my-hero/settings/security_analysis?tip=security_managers", task.task_link
    end
  end
end
