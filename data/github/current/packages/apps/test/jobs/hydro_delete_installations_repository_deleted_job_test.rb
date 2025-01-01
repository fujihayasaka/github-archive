# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroDeleteInstallationsRepositoryDeletedJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  setup do
    @queue = "hydro_delete_installations_repository_deleted"
    @schema = "github.repositories.v1.Deleted"

    @target = create(:credit_card_organization)
    @admin  = @target.admins.first

    @repo = create(:repository, :minimal, owner: @target)
  end

  test "deletes installations when repository is deleted" do
    installation = make_integration_installation(target: @target, repository: @repo, permissions: { "metadata" => :read })

    orchestration = RepositoryOrchestration.delete(@repo, actor: User.ghost)
    orchestration.execute(synchronous: true)

    perform_enqueued_jobs(only: [HydroDeleteInstallationsRepositoryDeletedJob, IntegrationInstallationRepositoryRemovalJob, UninstallIntegrationInstallationJob]) do
      perform_hydro_message_job(orchestration.build_hydro_event_message, schema: @schema, queue: @queue)
    end

    assert_nil IntegrationInstallation.find_by(id: installation.id)
  end
end
