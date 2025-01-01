# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class AutoMergeRequestTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include HydroTestHelpers
  include PullRequestIntegrationTestHelpers

  fixtures do
    @repo = create(:repository)
    @repo.allow_auto_merge(actor: @repo.owner)
    @pull = setup_pull_request(repository: @repo)
    @repo.protect_branch(@pull.base_ref_name, creator: @repo.owner, required_pull_request_reviews: {
      require_code_owner_reviews: true,
    }, entry_point: :test_case)
    @repo.add_member(@pull.user)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "setup works" do
    assert @pull.persisted?
  end

  test "can create with factory" do
    auto_merge_request = build(:auto_merge_request)
    assert auto_merge_request.save
  end

  test "create with invalid user id fails" do
    auto_merge_request = build(:auto_merge_request, user: nil)
    refute_predicate auto_merge_request, :valid?
    refute_empty auto_merge_request.errors[:user]
  end

  test "create with invalid pull request id fails" do
    auto_merge_request = build(:auto_merge_request, pull_request: nil)
    refute_predicate auto_merge_request, :valid?
    refute_empty auto_merge_request.errors[:pull_request]
  end

  test "create with unlisted enum string fails" do
    auto_merge_request = build(:auto_merge_request, merge_method: nil)
    refute_predicate auto_merge_request, :valid?
    refute_empty auto_merge_request.errors[:merge_method]
  end

  test "create with a closed pull request fails" do
    @pull.close(@pull.user)
    auto_merge_request = build(:auto_merge_request, pull_request: @pull)
    refute_predicate auto_merge_request, :valid?
    assert_equal "Pull request is closed", auto_merge_request.errors[:pull_request][0]
  end

  test "create with a merged pull request fails" do
    @pull.merge
    auto_merge_request = build(:auto_merge_request, pull_request: @pull)
    refute_predicate auto_merge_request, :valid?
    assert_equal "Pull request is closed", auto_merge_request.errors[:pull_request][0]
  end

  test "create with a draft pull request fails" do
    @pull.convert_to_draft(user: @pull.user)
    auto_merge_request = build(:auto_merge_request, pull_request: @pull)
    refute_predicate auto_merge_request, :valid?
    assert_equal "Pull request is a draft", auto_merge_request.errors[:pull_request][0]
  end

  test "creates auto-merge enabled issue event on creation" do
    auto_merge_request = create(:auto_merge_request)
    assert event = auto_merge_request.pull_request.events.find_by(event: "auto_merge_enabled"), "did not create event"
  end

  test "creates auto rebase enabled issue event on creation" do
    auto_merge_request = create(:auto_merge_request, merge_method: :auto_rebase_and_merge)
    assert event = auto_merge_request.pull_request.events.find_by(event: "auto_rebase_enabled"), "did not create event"
  end

  test "creates auto squash enabled issue event on creation" do
    auto_merge_request = create(:auto_merge_request, merge_method: :auto_squash_and_merge)
    assert event = auto_merge_request.pull_request.events.find_by(event: "auto_squash_enabled"), "did not create event"
  end

  test "creates disabled issue event on destruction" do
    auto_merge_request = create(:auto_merge_request)
    other_user = create(:user)

    auto_merge_request.disable(:manually_disabled, actor: other_user)

    assert auto_merge_request.destroyed?
    assert event = auto_merge_request.pull_request.events.find_by(event: "auto_merge_disabled"), "did not create event"
    assert_equal other_user.id, event.actor_id
  end

  test "allows disabling even with a ghost user" do
    auto_merge_request = create(:auto_merge_request)
    auto_merge_request.user.destroy

    # Aggressive caching requires a very hard reload to replicate.
    auto_merge_request = AutoMergeRequest.find(auto_merge_request.id)

    other_user = create(:user)

    auto_merge_request.disable(:manually_disabled, actor: other_user)

    assert auto_merge_request.destroyed?
    assert event = T.must(auto_merge_request.pull_request).events.find_by(event: "auto_merge_disabled"), "did not create event"
    assert_equal other_user.id, event.actor_id
  end

  test "gracefully skips already-enqueued PRs" do
    AutoMergeRequest.enqueue!(pull_request: @pull, user: @pull.user, merge_method: "merge")
    assert @pull.auto_merge_request

    assert_logged(
      "Body" => "duplicate AutoMergeRequest",
      "code.namespace" => "AutoMergeRequest",
      "code.function" => "enqueue!",
      "gh.pull_request.id" => @pull.id.to_s,
    ) do
      assert_nothing_raised do
        AutoMergeRequest.enqueue!(pull_request: @pull, user: @pull.user, merge_method: "merge")
      end
    end
  end

  context "merge method is allowed" do
    test "valid if merge method is merge and merge is allowed" do
      @repo.update_merge_settings(@repo.owner,
        merge_allowed: true
      )
      @repo.allow_auto_merge(actor: @repo.owner)

      auto_merge_request = build(:auto_merge_request, pull_request: @pull, merge_method: :auto_merge, user: @pull.user)
      assert_predicate auto_merge_request, :valid?
    end

    test "valid if merge method is squash and squash is allowed" do
      @repo.update_merge_settings(@repo.owner,
        squash_allowed: true
      )
      @repo.allow_auto_merge(actor: @repo.owner)

      auto_merge_request = build(:auto_merge_request, pull_request: @pull, merge_method: :auto_squash_and_merge, user: @pull.user)
      assert_predicate auto_merge_request, :valid?
    end

    test "valid if merge method is rebase and rebase is allowed" do
      @repo.update_merge_settings(@repo.owner,
        rebase_allowed: true
      )
      @repo.allow_auto_merge(actor: @repo.owner)

      auto_merge_request = build(:auto_merge_request, pull_request: @pull, merge_method: :auto_rebase_and_merge, user: @pull.user)
      assert_predicate auto_merge_request, :valid?
    end

    test "invalid if merge method is merge and merge is not allowed" do
      @repo.update_merge_settings(@repo.owner,
        merge_allowed: false
      )

      auto_merge_request = build(:auto_merge_request, pull_request: @pull, merge_method: :auto_merge)
      refute_predicate auto_merge_request, :valid?
      assert_equal "merge commits are not allowed on this repository", auto_merge_request.errors[:merge_method][0]
    end

    test "invalid if merge method is merge and merge is not allowed by the pull_request rule" do
      @repo.allow_auto_merge(actor: @repo.owner)
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
      create(:repository_rule_configuration, :pull_request, allowed_merge_methods: %w[squash rebase], repository_ruleset: ruleset)

      auto_merge_request = build(:auto_merge_request, pull_request: @pull, merge_method: :auto_merge, user: @pull.user)

      refute_predicate auto_merge_request, :valid?
      assert_equal "merge commits are not allowed on this repository", auto_merge_request.errors[:merge_method][0]
    end

    test "invalid if merge method is squash and squash is not allowed by the pull_request rule" do
      @repo.allow_auto_merge(actor: @repo.owner)
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
      create(:repository_rule_configuration, :pull_request, allowed_merge_methods: %w[merge rebase], repository_ruleset: ruleset)

      auto_merge_request = build(:auto_merge_request, pull_request: @pull, merge_method: :auto_squash_and_merge, user: @pull.user)

      refute_predicate auto_merge_request, :valid?
      assert_equal "squash merging is not allowed on this repository", auto_merge_request.errors[:merge_method][0]
    end

    test "invalid if merge method is rebase and rebase is not allowed by the pull_request rule" do
      @repo.allow_auto_merge(actor: @repo.owner)
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
      create(:repository_rule_configuration, :pull_request, allowed_merge_methods: %w[merge squash], repository_ruleset: ruleset)

      auto_merge_request = build(:auto_merge_request, pull_request: @pull, merge_method: :auto_rebase_and_merge, user: @pull.user)

      refute_predicate auto_merge_request, :valid?
      assert_equal "rebase merging is not allowed on this repository", auto_merge_request.errors[:merge_method][0]
    end

    test "invalid if merge method is squash and squash is not allowed" do
      @repo.update_merge_settings(@repo.owner,
        squash_allowed: false
      )

      auto_merge_request = build(:auto_merge_request, pull_request: @pull, merge_method: :auto_squash_and_merge)
      refute_predicate auto_merge_request, :valid?
      assert_equal "squash merging is not allowed on this repository", auto_merge_request.errors[:merge_method][0]
    end

    test "invalid if commit_message is too long" do
      msg = "\u043B" * 50000
      auto_merge_request = build(:auto_merge_request, pull_request: @pull, merge_method: :auto_merge, commit_message: msg)
      refute_predicate auto_merge_request, :valid?
      refute auto_merge_request.errors[:commit_message].empty?
    end

    test "invalid if commit_title is too long" do
      ttl = "🐹" * 100
      auto_merge_request = build(:auto_merge_request, pull_request: @pull, merge_method: :auto_merge, commit_title: ttl)
      refute_predicate auto_merge_request, :valid?
      refute auto_merge_request.errors[:commit_title].empty?
    end

    test "invalid if merge method is rebase and rebase is not allowed" do
      @repo.update_merge_settings(@repo.owner,
        rebase_allowed: false
      )

      auto_merge_request = build(:auto_merge_request, pull_request: @pull, merge_method: :auto_rebase_and_merge)
      refute_predicate auto_merge_request, :valid?
      assert_equal "rebase merging is not allowed on this repository", auto_merge_request.errors[:merge_method][0]
    end
  end

  context "hydro events" do
    test "auto-merge request is enabled" do
      @repo.protect_branch(@pull.base_ref, creator: @pull.user, required_pull_request_reviews: { require_code_owner_reviews: true }, required_signatures: true, entry_point: :test_case)
      @pull.create_merge_commit
      auto_merge_request = create(:auto_merge_request, pull_request: PullRequest.find(@pull.id), user: @pull.user)

      expected_hydro_message = {
        actor: Hydro::EntitySerializer.user(@pull.user),
        repository: Hydro::EntitySerializer.repository(@pull.repository),
        pull_request: Hydro::EntitySerializer.pull_request(@pull),
        protected_branch: Hydro::EntitySerializer.protected_branch(@pull.base_branch_rule_evaluator&.original_protected_branch),
        unfulfilled_protected_branch_policy_reason_codes: @pull.merge_state(viewer: @pull.user).unfulfilled_protected_branch_policy_reason_codes,
        auto_merge_request: Hydro::EntitySerializer.auto_merge_request(auto_merge_request)
      }
      assert_hydro_published(expected_hydro_message, schema: "github.v1.PullRequestAutoMergeEnable")
    end

    test "auto-merge request id disabled" do
      @repo.protect_branch(@pull.base_ref, creator: @pull.user, required_pull_request_reviews: { require_code_owner_reviews: true }, required_signatures: true, entry_point: :test_case)
      @pull.create_merge_commit
      auto_merge_request = create(:auto_merge_request, pull_request: PullRequest.find(@pull.id), user: @pull.user)

      expected_hydro_message = {
        actor: Hydro::EntitySerializer.user(@pull.user),
        repository: Hydro::EntitySerializer.repository(@pull.repository),
        pull_request: Hydro::EntitySerializer.pull_request(@pull),
        protected_branch: Hydro::EntitySerializer.protected_branch(@pull.base_branch_rule_evaluator&.original_protected_branch),
        disabled_message: :manually_disabled,
        unfulfilled_protected_branch_policy_reason_codes: @pull.merge_state(viewer: @pull.user).unfulfilled_protected_branch_policy_reason_codes,
        auto_merge_request: Hydro::EntitySerializer.auto_merge_request(auto_merge_request.reload)
      }

      auto_merge_request.disable(:manually_disabled, actor: @pull.user)

      assert_hydro_published(expected_hydro_message, schema: "github.v1.PullRequestAutoMergeDisable")
    end
  end

  context "minimal merge method" do
    test "returns :merge for :auto_merge" do
      auto_merge_request = create(:auto_merge_request, merge_method: :auto_merge)

      assert_equal :merge, auto_merge_request.minimal_merge_method
    end

    test "returns :squash for :auto_squash_and_merge" do
      auto_merge_request = create(:auto_merge_request, merge_method: :auto_squash_and_merge)

      assert_equal :squash, auto_merge_request.minimal_merge_method
    end

    test "returns :rebase for :auto_rebase_and_merge" do
      auto_merge_request = create(:auto_merge_request, merge_method: :auto_rebase_and_merge)

      assert_equal :rebase, auto_merge_request.minimal_merge_method
    end

    test "returns :merge for :merge_queue" do
      auto_merge_request = create(:auto_merge_request, merge_method: :merge_queue)

      assert_equal :merge, auto_merge_request.minimal_merge_method
    end

    test "returns :merge for :merge_queue_solo" do
      auto_merge_request = create(:auto_merge_request, merge_method: :merge_queue_solo)

      assert_equal :merge, auto_merge_request.minimal_merge_method
    end

    test "returns :merge for :merge_queue_jump" do
      auto_merge_request = create(:auto_merge_request, merge_method: :merge_queue_jump)

      assert_equal :merge, auto_merge_request.minimal_merge_method
    end
  end

  context "reason message" do
    reason_messages = {
      manually_disabled: "Manually disabled by user",
      base_missing: "Base branch no longer exists",
      closed: "Pull request was closed",
      converted_to_draft: "Pull request was converted to draft",
      push_from_non_writer: "Head branch was pushed to by a user without write access",
      base_changed_by_non_writer: "Base branch changed by a user without write access",
      denied: "Merge could not be authorized",
      draft: "Pull request is a draft",
      head_mismatch: "Head branch was modified",
      invalid_email: "Invalid email address",
      merge_commit_blocked: "Merge commits are not allowed on this repository",
      not_mergeable: "Pull Request is not mergeable",
      parent_mismatch: "Base branch was modified",
      protected_branch: "Base branch requires signed commits",
      rebase: "Rebase failed",
      rebase_merge_blocked: "Rebase merges are not allowed on this repository",
      rewrite: "Could not re-write the merge commit for some reason",
      squash_merge_blocked: "Squash merges are not allowed on this repository",
      merge_queue: "Merge queue setting changed",
      workflow_policy_update_error: "Tried to create or update workflow without `workflows` permission",
      repository_rule_violation: "Repository rule violations found",
    }

    AutoMergeRequest::VALID_DISABLE_REASON_CODES.each do |reason_code|
      test "gives correct message for #{reason_code} reason code" do
        assert_equal reason_messages[reason_code], AutoMergeRequest.reason_message(reason_code)
      end
    end
  end

  test "copies `repository_id` from the `pull_request` during create" do
    auto_merge_request = build(:auto_merge_request)

    pull_request = auto_merge_request.pull_request
    refute_nil pull_request.repository_id

    # ensure assigned from pull_request reference, so set value to nil if already set.
    auto_merge_request.repository_id = nil

    auto_merge_request.save

    refute_nil auto_merge_request.repository_id
    assert_equal auto_merge_request.repository_id, pull_request.repository_id
  end
end
