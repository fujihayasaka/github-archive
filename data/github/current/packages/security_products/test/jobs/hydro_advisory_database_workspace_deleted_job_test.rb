# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class HydroAdvisoryDatabaseWorkspaceDeletedJobTest < GitHub::TestCase
  include HydroTestHelpers
  include HydroMessageJobTestHelpers

  fixtures do
    @queue = "hydro_advisory_database_workspace_deleted"
    @schema = "github.repositories.v1.WorkspaceDeleted"

    @admin = create(:user, login: "WorkspaceDeletedJobTest-admin")
    @staff = create(:staff_admin_user, login: "WorkspaceDeletedJobTest-staff")
    @org = create(:organization, login: "WorkspaceDeletedJobTest-org")
    @parent_repo = create(:repository, owner: @org)
    @parent_repo.add_member(@admin, action: :admin)
    @advisory = create(:repository_advisory, :with_workspace, repository: @parent_repo, author: @admin)
  end

  test "adds an advisory timeline event to indicate that a workspace was deleted" do
    assert_changes -> { @advisory.events.count }, 1 do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job(deletion_hydro_message(actor_id: @admin.id), schema: @schema, queue: @queue)
      end
    end

    assert_equal "workspace_deleted", @advisory.events.last.event
  end

  test "includes the actor if they are authorized to manage the advisory" do
    assert_changes -> { @advisory.events.count }, 1 do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job(deletion_hydro_message(actor_id: @admin.id), schema: @schema, queue: @queue)
      end
    end

    assert_equal @admin, @advisory.events.last.actor
  end

  test "sets the actor to github's builtin staff user if they were a staff member who didn't have permissions on the advisory" do
    assert_changes -> { @advisory.events.count }, 1 do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job(deletion_hydro_message(actor_id: @staff.id), schema: @schema, queue: @queue)
      end
    end

    # Why is this comparing to ID specifically? Good question! It appears that the actor is not rehydrated when we commit the event in some cases, and I don't fully understand why this particular case is affected.
    # This was originally surfaced in this file via gauntlet.
    assert_equal User.staff_user.id, @advisory.events.last.actor_id
  end

  test "includes the actor if they were a staff member who DID have permissions on the advisory" do
    @parent_repo.add_member(@staff, action: :admin)
    assert @advisory.adminable_by?(@staff)
    assert_changes -> { @advisory.events.count }, 1 do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job(deletion_hydro_message(actor_id: @staff.id), schema: @schema, queue: @queue)
      end
    end

    assert_equal @staff, @advisory.events.last.actor
  end

  def deletion_hydro_message(actor_id: nil, repository_id: @advisory.workspace_repository.id, advisory_id: @advisory.id)
    message = {
      repository_id: repository_id,
      advisory_id: advisory_id,
      actor_id: actor_id,
    }
  end
end if GitHub.repository_advisories_enabled?
