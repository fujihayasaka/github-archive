# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroAppsRepositoryCreatedJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  context "Installation rate limit job is queued" do
    test "for new repositories" do
      user = create(:user)
      installation = make_integration_installation(target: user, permissions: { "metadata" => :read })
      repo = create(:repository, owner: user)

      message = {
        repository_id: repo.id
      }

      assert_enqueued_jobs 1, only: UpdateIntegrationInstallationRateLimitJob do
        perform_hydro_message_job(message, schema: "github.repositories.v1.Created", queue: "hydro_apps_repository_created")
      end
    end

    test "for forked repositories" do
      user = create(:user)
      installation = make_integration_installation(target: user, permissions: { "metadata" => :read })

      parent_repo = create(:repository)
      fork_repo = create(:repository, parent: parent_repo, owner: user)

      message = {
        repository_id: fork_repo.id
      }

      assert_enqueued_jobs 1, only: UpdateIntegrationInstallationRateLimitJob do
        perform_hydro_message_job(message, schema: "github.repositories.v1.Created", queue: "hydro_apps_repository_created")
      end
    end

    test "for repositories that have been destroyed" do
      repo = create(:repository)

      repo_id = repo.id

      message = {
        repository_id: repo_id
      }

      repo.destroy

      refute Repository.exists?(repo_id)

      assert_nothing_raised do
        perform_hydro_message_job(message, schema: "github.repositories.v1.Created", queue: "hydro_apps_repository_created")
      end
    end

  end
end
