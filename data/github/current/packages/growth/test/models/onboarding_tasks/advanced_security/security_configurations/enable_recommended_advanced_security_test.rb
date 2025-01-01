# typed: true
# frozen_string_literal: true

require "test_helper"

class OnboardingTasks::AdvancedSecurity::SecurityConfigurations::EnableRecommendedAdvancedSecurityTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)
  end

  context "#verify_task" do
    test "returns false if there is no repo security configuration applied to the org" do
      task = OnboardingTasks::AdvancedSecurity::SecurityConfigurations::EnableRecommendedAdvancedSecurity.new(
        taskable: @org,
        user: @owner
      )

      refute_predicate task, :verify_task
    end

    test "returns true if there is a repo security configuration applied to the org" do
      task = OnboardingTasks::AdvancedSecurity::SecurityConfigurations::EnableRecommendedAdvancedSecurity.new(
        taskable: @org,
        user: @owner
      )

      repo = create(:repository, owner: @org)

      RepositorySecurityConfiguration.create!(
        security_configuration_id: create(:security_configuration, :disabled, target: @org).id,
        state: :attached,
        repository_id: repo.id,
        organization_id: @org.id
      )

      assert_predicate task, :verify_task
    end
  end
end
