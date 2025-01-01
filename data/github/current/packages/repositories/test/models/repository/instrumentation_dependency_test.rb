# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryInstrumentationDependencyTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")
    @maddox   = create(:user, login: "maddox")
    @mojombo  = create(:user, login: "mojombo2", plan: "medium")
    @pj       = create(:user, login: "pj",       plan: "medium")

    @ambition = create(:private_repository, name: "ambition", owner: @defunkt)
    @facebox  = create(:repository, name: "facebox",  owner: @defunkt)
    @grit     = create(:repository, name: "grit",     owner: @mojombo)
    @simple   = create(:repository, name: "simple",   owner: @defunkt)
  end

  test "instruments when creating repository" do
    GitHub.stubs(:hydro_enabled?).returns(true)
    events = subscribe "repo.create"
    t = Time.now
    Repository.any_instance.stubs(:pushed_at).returns(t)
    @facebox = create(:repository, :full_creation, {
      owner: @defunkt,
      created_by_user_id: @maddox.id,
      gitignore_template: "Python",
      license_template: "mit",
      auto_init: true,
      template: false,
    })
    expected_payload = {
      repo: @facebox.name_with_owner,
      repo_id: @facebox.id,
      public_repo: @facebox.public?,
      user: @defunkt.login,
      user_id: @defunkt.id,
      visibility: :public,
      fork_source: @facebox.name_with_owner,
      fork_source_id: @facebox.id,
      actor: @maddox.login,
      actor_id: @maddox.id,
    }
    expected_hydro_payload = {
      actor: {
        analytics_tracking_id: @maddox.analytics_tracking_id,
        billing_plan: @maddox.plan.name,
        created_at: @maddox.created_at,
        global_relay_id: @maddox.global_relay_id,
        next_global_id: @maddox.next_global_id,
        id: @maddox.id,
        login: @maddox.login,
        spammy: @maddox.spammy,
        spamurai_classification: "SPAMURAI_CLASSIFICATION_UNKNOWN",
        type: "USER",
        time_zone_name: nil,
        avatar_url: @maddox.primary_avatar_url,
        display_login: @maddox.display_login,
      },
      repository: {
        global_relay_id: @facebox.global_relay_id,
        id: @facebox.id,
        network_id: @facebox.network_id,
        name: @facebox.name,
        description: @facebox.description,
        created_at: @facebox.created_at,
        updated_at: @facebox.updated_at,
        pushed_at: t,
        visibility: "PUBLIC",
        template: false,
        default_branch: Configurable::DefaultNewRepoBranch.recommended_name,
        organization_id: @facebox.organization_id,
        owner_id: @facebox.owner_id,
        wiki_world_writable: false,
      },
      gitignore_template: "Python",
      license_template: "mit",
      init_with_readme: true,
      owner: Hydro::EntitySerializer.user(@facebox.owner),
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
    assert_hydro_published(expected_hydro_payload, schema: "github.v1.RepositoryCreate")
  end

  test "Repository create publishes github.platform_health.v1.UserGeneratedContent" do
    GitHub.stubs(:hydro_enabled?).returns(true)
    now = Time.now
    Repository.any_instance.stubs(:pushed_at).returns(now)
    repo = create(:repository, :full_creation, {
      owner: @defunkt,
      created_by_user_id: @maddox.id,
      gitignore_template: "Python",
      license_template: "mit",
      auto_init: true,
      template: false,
    })

    message = {
      request_context: nil,
      spamurai_form_signals: nil,
      action_type: :CREATE,
      content_type: :REPOSITORY_DESCRIPTION,
      actor: Hydro::EntitySerializer.user(@maddox),
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.RepositoryCreate"),
      content_database_id: repo.id,
      content_global_relay_id: repo.global_relay_id,
      content_created_at: repo.created_at,
      content_updated_at: repo.updated_at,
      title: Hydro::EntitySerializer.specimen_data(repo.name),
      content: Hydro::EntitySerializer.specimen_data(repo.description),
      parent_content_author: nil,
      parent_content_database_id: nil,
      parent_content_global_relay_id: nil,
      parent_content_created_at: nil,
      parent_content_updated_at: nil,
      owner: Hydro::EntitySerializer.user(@defunkt),
      repository: Hydro::EntitySerializer.repository(repo),
      content_visibility: :PUBLIC,
    }

    with_hydro_publisher(GitHub.hydro_publisher) do
      assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
    end
  end

  test "#add_member instruments membership event to hydro", skip_enterprise: true do
    GitHub.hydro_publisher.sink&.messages&.clear

    @ambition.add_member(@pj)
    assert_hydro_messages(count: 1, schema: "github.v1.MembershipUpdate")
  end

  test "instruments changing repository visibility from public to private", skip_enterprise: true do
    assert @grit.public?


    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @grit.toggle_visibility(actor: @grit.owner) }

    assert @grit.reload.private?

    assert_hydro_published({
      name_with_owner: @grit.name_with_owner,
      repository_id: @grit.id,
      is_private: @grit.private?,
      is_fork: @grit.fork?,
      visibility: @grit.visibility,
    }, schema: "github.v1.RepositoryVisibilityChanged")

    assert_hydro_messages(count: 1, schema: "github.v1.RepositoryVisibilityChanged")
  end

  test "instruments changing repository visibility from public to private for search indexing", skip_enterprise: true do
    GitHub.flipper[:geyser_denylist].disable
    example_repo(:simple, @grit)

    Timecop.freeze do
      assert @grit.public?

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @grit.toggle_visibility(actor: @grit.owner) }

      assert @grit.reload.private?

      assert_hydro_published({
        change: :VISIBILITY_CHANGED,
        repository: Hydro::EntitySerializer.repository(@grit),
        ref: "refs/heads/#{@grit.default_branch}",
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

      assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
    end
  end

  test "instruments changing repository visibility from private to public", skip_enterprise: true do
    assert @ambition.private?

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @ambition.toggle_visibility(actor: @ambition.owner) }

    assert @ambition.reload.public?

    assert_hydro_published({
      name_with_owner: @ambition.name_with_owner,
      repository_id: @ambition.id,
      is_private: @ambition.private?,
      is_fork: @ambition.fork?,
      visibility: @ambition.visibility,
      feature_flags: %w[token_scanning_service_ingest]
    }, schema: "github.v1.RepositoryVisibilityChanged")

    assert_hydro_messages(count: 1, schema: "github.v1.RepositoryVisibilityChanged")
  end

  test "instruments changing repository visibility from private to public has feature flags", skip_enterprise: true do
    example_repo(:simple, @ambition)

    assert @ambition.private?

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @ambition.toggle_visibility(actor: @ambition.owner) }
    assert @ambition.reload.public?

    assert_hydro_published({
      name_with_owner: @ambition.name_with_owner,
      repository_id: @ambition.id,
      is_private: @ambition.private?,
      is_fork: @ambition.fork?,
      visibility: @ambition.visibility,
      feature_flags: ["token_scanning_service_ingest"],
    }, schema: "github.v1.RepositoryVisibilityChanged")

    assert_hydro_messages(count: 1, schema: "github.v1.RepositoryVisibilityChanged")
  end

  test "instruments changing config repository visibility from private to public", skip_enterprise: true do
    Timecop.freeze do
      owner = create(:user)
      GitHub.context.push({ actor_id: owner.id })
      repository = create(:private_repository, owner: owner, name: owner.login, from_example: :profile_config)

      assert repository.private?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repository.toggle_visibility(actor: owner) }
      assert repository.reload.public?

      readme_body = repository.preferred_readme.data
      assert_hydro_published(
        {
          repository: Hydro::EntitySerializer.repository(repository.reload),
          owner: Hydro::EntitySerializer.user(owner),
          actor: Hydro::EntitySerializer.user(owner),
          change_type: :REPO_VISIBILITY_CHANGED_TO_PUBLIC,
          readme_body: Hydro::EntitySerializer.specimen_data(readme_body)
        },
        schema: "github.v1.ProfileReadmeAction",
        ignore_extra_keys: true
      )

      assert_hydro_messages(count: 1, schema: "github.v1.ProfileReadmeAction")
    end
  end

  test "instruments changing repository visibility from private to public search indexing", skip_enterprise: true do
    Timecop.freeze do
      GitHub.flipper[:geyser_denylist].disable
      assert @ambition.private?

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @ambition.toggle_visibility(actor: @ambition.owner) }

      assert @ambition.reload.public?

      assert_hydro_published({
        change: :VISIBILITY_CHANGED,
        repository: Hydro::EntitySerializer.repository(@ambition.reload),
        ref: "refs/heads/#{@ambition.default_branch}",
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

      assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
    end
  end

  test "instruments changing repository visibility is no-op when owner is denylisted", skip_enterprise: true do
    example_repo(:simple, @grit)

    # flag the feature off for this repo, then trigger Hydro event from vis change
    GitHub.flipper[:geyser_denylist].enable_actor(@grit.owner)

    assert @grit.public?

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @grit.toggle_visibility(actor: @grit.owner) }
    assert @grit.reload.private?

    assert_hydro_messages(count: 0, schema: "github.search.v0.RepositoryChanged")
  end

  test "instruments repository disabled action for search indexing", skip_enterprise: true do
    GitHub.flipper[:geyser_denylist].disable
    example_repo(:simple, @grit)
    staff = create(:staff_admin_user)
    @grit.access.disable("tos", staff)
    assert @grit.reload.access.disabled?

    assert_hydro_published({
      change: :DISABLED,
      repository: Hydro::EntitySerializer.repository(@grit),
      ref: "refs/heads/#{@grit.default_branch}",
    }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

    assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
  end

  test "instruments repository disabled and re-enabled action for search indexing", skip_enterprise: true do
    GitHub.flipper[:geyser_denylist].disable
    example_repo(:simple, @grit)
    staff = create(:staff_admin_user)
    @grit.access.disable("size", staff)
    assert @grit.reload.access.disabled?

    # this is the expected DISABLED event
    assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
    # clear the message buffer
    GitHub.hydro_publisher.sink&.messages&.clear

    @grit.access.enable(@grit.owner)
    refute @grit.reload.disabled?

    # (re)enabling the repo ought to produce a RESTORED event
    assert_hydro_published({
      change: :RESTORED,
      repository: Hydro::EntitySerializer.repository(@grit),
      ref: "refs/heads/#{@grit.default_branch}",
    }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

    assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
  end

  test "instruments when repository is archived", skip_enterprise: true do
    assert_equal @grit.archived?, false

    assert @grit.set_archived(synchronous: true)

    assert @grit.archived?

    assert_hydro_published({
      repository_id: @grit.id,
      repository_global_id: @grit.global_relay_id,
      is_archived: true,
      actor_id: 0,
    }, schema: "github.v1.RepositoryArchivedStatusChanged")

    assert_hydro_messages(count: 1, schema: "github.v1.RepositoryArchivedStatusChanged")
  end

  test "instruments when repository is unarchived", skip_enterprise: true do
    @grit.set_archived(synchronous: true)

    assert @grit.archived?

    @grit.unset_archived(synchronous: true)

    assert_equal @grit.archived?, false

    assert_hydro_published({
      repository_id: @grit.id,
      repository_global_id: @grit.global_relay_id,
      is_archived: false,
      actor_id: 0,
    }, schema: "github.v1.RepositoryArchivedStatusChanged")

    assert_hydro_messages(count: 2, schema: "github.v1.RepositoryArchivedStatusChanged")
  end

  test "instruments when adding member" do
    events = subscribe "repo.add_member"
    expected_payload = {
      repo: @ambition.name_with_owner,
      repo_id: @ambition.id,
      public_repo: @ambition.public?,
      user: @pj.login,
      user_id: @pj.id,
      visibility: :private,
      fork_source: @ambition.name_with_owner,
      fork_source_id: @ambition.id,
      actor: @defunkt.login,
      actor_id: @defunkt.id,
      permission: :write
    }

    @ambition.add_member(@pj)

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instruments when adding member with actor" do
    events = subscribe "repo.add_member"
    expected_payload = {
      repo: @ambition.name_with_owner,
      repo_id: @ambition.id,
      public_repo: @ambition.public?,
      user: @pj.login,
      user_id: @pj.id,
      visibility: :private,
      fork_source: @ambition.name_with_owner,
      fork_source_id: @ambition.id,
      actor: @defunkt.login,
      actor_id: @defunkt.id,
      permission: :write
    }

    @ambition.add_member(@pj, @defunkt)

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "doesn't create a event when a member is removed" do
    GitHub.stratocaster.clear_timelines("repo:#{@ambition.id}")

    @ambition.remove_member(@mojombo, @defunkt)
    assert_equal 0, GitHub.stratocaster.events("repo:#{@ambition.id}").size
  end

  test "#remove_member instruments membership event to hydro", skip_enterprise: true do
    @ambition.add_member(@pj)

    GitHub.hydro_publisher.sink&.messages&.clear

    @ambition.remove_member(@pj)
    assert_hydro_messages(count: 1, schema: "github.v1.MembershipUpdate")
  end

  test "instruments when removing member" do
    expected_payload = {
      repo: @ambition.name_with_owner,
      repo_id: @ambition.id,
      public_repo: @ambition.public?,
      user: @mojombo.login,
      user_id: @mojombo.id,
      visibility: :private,
      fork_source: @ambition.name_with_owner,
      fork_source_id: @ambition.id,
      actor: @defunkt.login,
      actor_id: @defunkt.id,
    }

    @ambition.add_member(@mojombo, @defunkt, false)

    events = subscribe "repo.remove_member"
    @ambition.remove_member(@mojombo)

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instruments when removing member with actor" do
    expected_payload = {
      repo: @ambition.name_with_owner,
      repo_id: @ambition.id,
      public_repo: @ambition.public?,
      user: @mojombo.login,
      user_id: @mojombo.id,
      visibility: :private,
      fork_source: @ambition.name_with_owner,
      fork_source_id: @ambition.id,
      actor: @pj.login,
      actor_id: @pj.id,
    }

    @ambition.add_member(@mojombo, @defunkt, false)

    events = subscribe "repo.remove_member"
    @ambition.remove_member(@mojombo, @pj)

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "does not instrument when removing non-member" do
    events = subscribe "repo.remove_member"
    @ambition.remove_member(@mojombo)

    assert_nil events.pop, "an event was not expected"
  end

  test "instruments when setting a repository as archived" do
    GitHub.context.push(actor_id: @simple.owner.id)
    events = subscribe "repo.archived"
    @simple.set_archived(synchronous: true)

    expected_payload = {
      visibility: :public,
      actor_id: @simple.owner.id,
      actor: @simple.owner.login,
      repo: @simple.name_with_owner,
      repo_id: @simple.id,
      public_repo: @simple.public?,
      user: @simple.owner.login,
      user_id: @simple.owner.id,
      fork_source: @simple.name_with_owner,
      fork_source_id: @simple.id,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "does not instrument event when setting already archived repository as archived" do
    @simple.set_archived
    refute_predicate @simple, :maintained?

    events = subscribe "repo.archived"
    @simple.set_archived

    assert_equal 0, events.count
  end

  test "instruments when unsetting a repository as archived" do
    GitHub.context.push(actor_id: @simple.owner.id)
    @simple.set_archived(synchronous: true)
    refute_predicate @simple, :maintained?
    events = subscribe "repo.unarchived"
    @simple.unset_archived(synchronous: true)

    expected_payload = {
      visibility: :public,
      actor_id: @simple.owner.id,
      actor: @simple.owner.login,
      repo: @simple.name_with_owner,
      repo_id: @simple.id,
      public_repo: @simple.public?,
      user: @simple.owner.login,
      user_id: @simple.owner.id,
      fork_source: @simple.name_with_owner,
      fork_source_id: @simple.id,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "does not instrument event for unarchived repository when unsetting archived" do
    assert_predicate @simple, :maintained?

    events = subscribe "repo.unarchived"
    @simple.unset_archived(synchronous: true)

    assert_equal 0, events.count
  end

  context "details updated event" do
    test "publishes event on description update" do
      description = "🎉 some description"
      assert @simple.update(description: description)

      message = {
        actor: Hydro::EntitySerializer.user(User.ghost),
        repository: Hydro::EntitySerializer.repository(@simple),
        description: description,
        homepage: nil,
      }

      assert_hydro_messages(count: 1, schema: "github.repositories.v1.RepositoryDetailsUpdated")
      assert_hydro_published_partial(message, schema: "github.repositories.v1.RepositoryDetailsUpdated")
    end

    test "publishes event on homepage + details update" do
      homepage = "some homepage"
      description = "🎉 some description"
      assert @simple.update(description: description, homepage: homepage)

      message = {
        actor: Hydro::EntitySerializer.user(User.ghost),
        repository: Hydro::EntitySerializer.repository(@simple),
        description: description,
        homepage: homepage,
      }

      assert_hydro_messages(count: 1, schema: "github.repositories.v1.RepositoryDetailsUpdated")
      assert_hydro_published_partial(message, schema: "github.repositories.v1.RepositoryDetailsUpdated")
    end
  end
end
