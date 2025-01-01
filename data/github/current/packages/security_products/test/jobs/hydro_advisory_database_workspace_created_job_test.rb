# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class HydroAdvisoryDatabaseWorkspaceCreatedJobTest < GitHub::TestCase
  include HydroTestHelpers
  include HydroMessageJobTestHelpers

  fixtures do
    @queue = "hydro_advisory_database_workspace_created"
    @schema = "github.repositories.v1.WorkspaceCreated"

    @admin = create(:user, login: "WorkspaceCreatedJobTest-admin")
    @rando = create(:user, login: "WorkspaceCreatedJobTest-pvr-author")
    @staff = create(:staff_admin_user, login: "WorkspaceCreatedJobTest-staff")
    @org = create(:organization, login: "WorkspaceCreatedJobTest-org")
    @parent_repo = create(:repository, owner: @org)
    @parent_repo.add_member(@admin, action: :admin)
    @advisory = create(:repository_advisory, :with_workspace, repository: @parent_repo, author: @admin)
  end

  test "adds an advisory timeline event to indicate that a workspace was created" do
    assert_changes -> { @advisory.events.count }, 1 do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job(creation_hydro_message, schema: @schema, queue: @queue)
      end
    end

    assert_equal "workspace_created", @advisory.events.last.event
  end

  test "includes the actor if they are authorized to manage the advisory" do
    assert_changes -> { @advisory.events.count }, 1 do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job(creation_hydro_message(actor_id: @admin.id), schema: @schema, queue: @queue)
      end
    end

    assert_equal @admin, @advisory.events.last.actor
  end

  test "includes the actor if it was an external advisory and they are the author" do
    pvr_advisory = create(:pending_pvd_repo_advisory, :with_workspace, repository: @parent_repo)
    pvr_submitter = pvr_advisory.author

    assert_changes -> { pvr_advisory.events.count }, 1 do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job(creation_hydro_message(actor_id: pvr_submitter.id, repository_id: pvr_advisory.workspace_repository.id, advisory_id: pvr_advisory.id), schema: @schema, queue: @queue)
      end
    end

    assert_equal pvr_submitter, pvr_advisory.events.last.actor
  end

  test "sets the actor to Github's builtin staff user if they were a staff member who didn't have permissions on the advisory" do
    assert_changes -> { @advisory.events.count }, 1 do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job(creation_hydro_message(actor_id: @staff.id, repository_id: @advisory.workspace_repository.id, advisory_id: @advisory.id), schema: @schema, queue: @queue)
      end
    end

    # Why is this comparing to ID specifically? Good question! It appears that the actor is not rehydrated when we commit the event in some cases, and I don't fully understand why this particular case is affected.
    # Signs in the "deleted_job" file point to this also being a guantlet surfaced issue if we don't move to ID.
    assert_equal User.staff_user.id, @advisory.events.last.actor_id
  end

  test "includes the actor if they were a staff member who DID have permissions on the advisory" do
    @parent_repo.add_member(@staff, action: :admin)
    assert @advisory.adminable_by?(@staff)
    assert_changes -> { @advisory.events.count }, 1 do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job(creation_hydro_message(actor_id: @staff.id, repository_id: @advisory.workspace_repository.id, advisory_id: @advisory.id), schema: @schema, queue: @queue)
      end
    end

    assert_equal @staff, @advisory.events.last.actor
  end

  test "includes the actor if they were a staff member who WAS a PVR author" do
    pvr_advisory = create(:pending_pvd_repo_advisory, :with_workspace, repository: @parent_repo, author: @staff)
    assert_changes -> { pvr_advisory.events.count }, 1 do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job(creation_hydro_message(actor_id: @staff.id, repository_id: pvr_advisory.workspace_repository.id, advisory_id: pvr_advisory.id), schema: @schema, queue: @queue)
      end
    end
    assert_equal @staff, pvr_advisory.events.last.actor
  end

  test "is a no-op if the workspace is not active" do
    workspace_repository = @advisory.workspace_repository
    workspace_repository.remove(@admin)
    refute_predicate workspace_repository.reload, :active?
    assert_no_changes -> { @advisory.events.count } do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job(creation_hydro_message(actor_id: @admin.id, repository_id: workspace_repository.id, advisory_id: @advisory.id), schema: @schema, queue: @queue)
      end
    end
  end

  test "is a no-op if the workspace does not have an parent advisory" do
    workspace_repository = @advisory.workspace_repository
    @advisory.update(workspace_repository_id: nil)
    assert_nil workspace_repository.reload.parent_advisory
    assert_no_changes -> { @advisory.events.count } do
      perform_hydro_message_job(creation_hydro_message(actor_id: @admin.id, repository_id: workspace_repository.id, advisory_id: @advisory.id), schema: @schema, queue: @queue)
    end
  end

  def creation_hydro_message(actor_id: nil, repository_id: @advisory.workspace_repository.id, advisory_id: @advisory.id)
    message = {
      repository_id: repository_id,
      advisory_id: advisory_id,
      actor_id: actor_id,
    }
  end
end if GitHub.repository_advisories_enabled?
