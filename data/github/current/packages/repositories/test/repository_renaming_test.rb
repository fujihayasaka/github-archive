# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryRenamingTest < GitHub::TestCase
  include HydroTestHelpers

  setup do
    @repo = create(:repository)
  end

  test "doesn't lock the repository when submitting the rename job" do
    refute @repo.locked

    @repo.rename("some-new-repo-name")

    refute @repo.reload.locked
  end

  test "renaming a repository as owner -> rebuilds the Pages site" do
    owner = @repo.owner
    @repo.expects(:rebuild_pages).with(owner, nil)
    @repo.rename("repo-#{SecureRandom.hex(4)}", actor: owner)
  end

  test "renaming a repository as collaborator -> rebuilds the Pages site" do
    collaborator = create(:user)
    @repo.add_member(collaborator)
    @repo.expects(:rebuild_pages).with(collaborator, nil)
    @repo.rename("repo-#{SecureRandom.hex(4)}", actor: collaborator)
  end

  test "existing lock on the repository is not modified by a rename" do
    @repo.lock_including_descendants!(Repository::LockDependency::BILLING)
    assert @repo.locked

    perform_enqueued_jobs(only: [DeliverHookEventJob]) do
      @repo.rename("some-new-repo-name")
    end

    assert @repo.reload.locked
    assert_equal Repository::LockDependency::BILLING, @repo.lock_reason
  end

  test "publishes rename event to hydro" do
    GitHub.stubs(:hydro_enabled?).returns(true)
    now = Time.now.beginning_of_day

    Timecop.freeze(now) do
      repo = create(:repository)
      old_name = repo.name
      owner = repo.owner
      new_name = "repo-#{SecureRandom.hex(4)}"

      expected_hydro_payload = {
        actor: {
          analytics_tracking_id: owner.analytics_tracking_id,
          billing_plan: owner.plan.name,
          created_at: owner.created_at,
          global_relay_id: owner.global_relay_id,
          next_global_id: owner.next_global_id,
          id: owner.id,
          login: owner.login,
          spammy: owner.spammy,
          spamurai_classification: "SPAMURAI_CLASSIFICATION_UNKNOWN",
          type: "USER",
          time_zone_name: nil,
          avatar_url: owner.primary_avatar_url,
          display_login: owner.display_login,
        },
        repository: {
          global_relay_id: repo.global_relay_id,
          id: repo.id,
          network_id: repo.network_id,
          name: new_name,
          description: repo.description,
          created_at: repo.created_at,
          updated_at: repo.updated_at,
          pushed_at: repo.pushed_at,
          visibility: "PUBLIC",
          template: false,
          default_branch: "master",
          organization_id: repo.organization_id,
          owner_id: repo.owner_id,
          wiki_world_writable: false,
        },
        previous_name: old_name,
        current_name: new_name,
        spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(GitHub.context[:spamuri_form_signals]),
      }

      repo.rename(new_name, actor: owner)

      assert_hydro_published(expected_hydro_payload, schema: "github.v1.RepositoryRename")
    end
  end
end
