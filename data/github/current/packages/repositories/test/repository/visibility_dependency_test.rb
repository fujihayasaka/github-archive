# typed: false
# frozen_string_literal: true

require "test_helper"

class RepositoryVisibilityDependencyTest < GitHub::TestCase
  fixtures do
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")
    @maddox   = create(:user, login: "maddox")
    @member   = create(:user, login: "member")
    @mojombo  = create(:user, login: "mojombo2", plan: "medium")

    @ambition = create(:private_repository, name: "ambition", owner: @defunkt)
    @grit     = create(:repository, name: "grit",     owner: @mojombo)

    @biz = create(:business, name: "Salsa, Inc", owners: [@maddox], seats: 20)

    @biz_org  = create(:organization, plan: GitHub::Plan.business_plus, admins: [@maddox], business: @biz)
  end

  context "instrumenting config repo visibility change" do
    test "publishes user.profile_readme_action when the a user config repository with a readme is made public" do
      received_global_instrumenter_event = false

      GlobalInstrumenter.subscribe("user.profile_readme_action") do |_event, _start, _ending, _transaction_id, _payload|
        received_global_instrumenter_event = true
      end

      user_repo = create(:private_repository, name: "defunkt", owner: @defunkt, from_example: :profile_config)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { user_repo.toggle_visibility(actor: @defunkt, visibility: "public") }

      assert received_global_instrumenter_event
    end

    test "publishes when an org config repository with a profile readme is made public" do
      received_global_instrumenter_event = false

      GlobalInstrumenter.subscribe("organization.profile_readme_action") do |_event, _start, _ending, _transaction_id, _payload|
        received_global_instrumenter_event = true
      end

      org_repo = create(:private_repository, name: ".github", owner: create(:organization, name: "Testorg"), from_example: :org_profile)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { org_repo.toggle_visibility(actor: @defunkt, visibility: "public") }

      assert received_global_instrumenter_event
    end
  end

  context "visibility" do
    test "returns private for a private repository" do
      repo = create(:private_repository, owner: @maddox)
      assert_equal repo.visibility, Repository::PRIVATE_VISIBILITY
    end

    test "returns public for a public repository" do
      repo = create(:public_repository, owner: @maddox)
      assert_equal repo.visibility, Repository::PUBLIC_VISIBILITY
    end

    test "returns internal for an internal repository" do
      repo = create(:internal_repository, owner: @biz_org, public: false)
      assert_equal :internal, repo.visibility.to_sym
      assert_equal repo.visibility, Repository::INTERNAL_VISIBILITY
    end
  end

  test "set_visibility locks the repo" do
    refute_predicate @ambition, :locked?
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      VisibilityRepositoryOrchestration.stop_after_step = :lock_repo
      @ambition.set_visibility(actor: @defunkt, visibility: "public")
    end
    assert_predicate @ambition.reload, :locked?
    assert_equal @ambition.lock_reason, Repository::LockDependency::MOVING

    refute_predicate @grit, :locked?
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      VisibilityRepositoryOrchestration.stop_after_step = :lock_repo
      @grit.set_visibility(actor: @mojombo, visibility: "private")
    end

    assert_predicate @grit.reload, :locked?
    assert_equal @grit.lock_reason, Repository::LockDependency::MOVING
  end

  test "async_toggle_repository_visibility locks a private forks and its descendants" do
    @ambition.add_member(@member)
    @ambition.add_member(@mojombo)
    fork = create(:fork_repository, forker: @member, fork_repo: @ambition)
    fork2 = create(:fork_repository, forker: @mojombo, fork_repo: @ambition)

    refute fork.locked_on_move?
    refute fork2.locked_on_move?

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      VisibilityRepositoryOrchestration.stop_after_step = :lock_forks
      @ambition.set_visibility(actor: @defunkt, visibility: "public")
    end

    assert fork.reload.locked_on_move?
    assert_equal fork.reload.lock_reason, Repository::LockDependency::MOVING
    assert fork2.reload.locked_on_move?
    assert_equal fork2.reload.lock_reason, Repository::LockDependency::MOVING
  end

  test "async_toggle_repository_visibility does not lock public forks and its descendants" do
    fork = create(:fork_repository, forker: @member, fork_repo: @grit)
    fork2 = create(:fork_repository, forker: @maddox, fork_repo: @grit)

    refute fork.locked_on_move?
    refute fork2.locked_on_move?

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      VisibilityRepositoryOrchestration.stop_after_step = :lock_forks
      @grit.set_visibility(actor: @mojombo, visibility: "private")
    end

    refute fork.reload.locked_on_move?
    refute fork2.reload.locked_on_move?
  end
end
