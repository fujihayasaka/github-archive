# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroRestorePackagesRepositoryRestoreJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  setup do
    Spokesd.enable_spokesd
    @queue = "hydro_restore_packages_repository_restore"
    @schema = "github.repositories.v2.Restored"

    @user = create :user
    @repo = create :repository, owner: @user
  end

  test "restores packages deleted from repo deletion" do
    create :registry_package, repository: @repo

    perform_enqueued_hydro_jobs(only: [HydroDeletePackagesRepositoryDeletedJob], allowed_primary_query_count: 13) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        @repo.remove(@actor, synchronous: true)
      end
    end

    assert @repo.packages.first.deleted?

    message = { repository_id: @repo.id, actor_id: @user.id, deleted_at: @repo.deleted_at }
    perform_hydro_message_job(message, schema: @schema, queue: @queue)

    refute @repo.packages.first.deleted?
  end
end
