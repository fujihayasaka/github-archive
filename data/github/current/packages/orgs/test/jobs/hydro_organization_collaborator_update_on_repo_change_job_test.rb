# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroOrganizationCollaboratorUpdateOnRepoChangeJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @org = create(:organization)
    @business = create(:business, organizations: [@org])
    @repo = create(:repository, owner: @org)
  end

  test "enqueues collaborator backfill job on deleted event" do
    enable_feature_flag(:collaborator_cache_write)
    message = { repository_id: @repo.id }

    assert_enqueued_jobs 1, only: OrganizationCollaboratorBackfillJob do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Deleted", queue: "hydro_organization_collaborator_update_on_repo_change")
    end
  end

  test "does not enqueue collaborator backfill job on deleted event if FF is disabled" do
    disable_feature_flag(:collaborator_cache_write)
    message = { repository_id: @repo.id }

    assert_enqueued_jobs 0, only: OrganizationCollaboratorBackfillJob do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Deleted", queue: "hydro_organization_collaborator_update_on_repo_change")
    end
  end

  test "enqueues collaborator backfill job on restored event" do
    enable_feature_flag(:collaborator_cache_write)
    message = { repository_id: @repo.id }

    assert_enqueued_jobs 1, only: OrganizationCollaboratorBackfillJob do
      perform_hydro_message_job(message, schema: "github.repositories.v2.Restored", queue: "hydro_organization_collaborator_update_on_repo_change")
    end
  end

  test "does not enqueue collaborator backfill job on restored event if FF is disabled" do
    disable_feature_flag(:collaborator_cache_write)
    message = { repository_id: @repo.id }

    assert_enqueued_jobs 0, only: OrganizationCollaboratorBackfillJob do
      perform_hydro_message_job(message, schema: "github.repositories.v2.Restored", queue: "hydro_organization_collaborator_update_on_repo_change")
    end
  end
end
