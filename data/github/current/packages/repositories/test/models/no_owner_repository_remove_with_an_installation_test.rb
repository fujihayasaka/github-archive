# typed: true
# frozen_string_literal: true

require "test_helper"

class NoOwnerRepositoryRemoveWithAnInstallationTest < GitHub::TestCase
  include RepositoriesTestHelper
  include HydroMessageJobTestHelpers

  fixtures do
    @user  = create :user, plan: "medium"
    @repo1 = create :repository, owner: @user
    @repo2 = create :repository, owner: @user
  end

  test "queues an IntegrationInstallationRepositoryRemovalJob" do
    installation = make_integration_installation(
      target: @user,
      repository: @repo1,
      permissions: { "metadata" => :read },
    )

    # IntegrationInstallationRepositoryRemovalJob is invoked when a repo is deleted
    assert_enqueued_jobs(1, only: IntegrationInstallationRepositoryRemovalJob) do
      non_existent_owner(@repo1)
      perform_enqueued_hydro_jobs(only: [HydroDeleteInstallationsRepositoryDeletedJob], allowed_primary_query_count: 5) do
        @repo1.remove(@user, synchronous: true)
      end
    end
  end
end
