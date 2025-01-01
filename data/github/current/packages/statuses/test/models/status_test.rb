# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class StatusTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    @johndoe = create(:user, login: "johndoe", plan: "medium")
    @spammer = create :user, spammy: true

    @grit = create(:repository, name: "grit", owner: @johndoe)
    @spammy_repo = create :repository, owner: @spammer

    @sha1 = "1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec" # SHA of 'master' and 'merged-branch'
    @tree1 = "9ad5126eba69a9ab519e7bafe9328caff5c614cd"
    @sha2 = "86264f45ff4bcd3da195f5c83f7e414ed4a71628" # SHA of 'lazy_delegator', 'unmerged-branch-1', and 'unMERGED-branch-2'
    @tree2 = "ad0e5c6cda4b7e2e46cc45e42a72eab4aa2e8109"
    @sha3 = "fb58d3284dbf05e05d8c2ab04ff5bfe853b67d88" # another random SHA in the test repo

    reset_repo_root
    example_repo :mojombo_grit, @grit, @spammy_repo # rubocop:disable GitHub/UseFromExampleInRepositoryFactory

    @grit.update_default_branch("master")
  end

  test "defaults to 'unknown' state" do
    assert_equal "unknown", Status.new(sha: @sha1, repository: @grit).state
  end

  test "populates commit_oid field on save" do
    status = Status.new(sha: @sha1, repository: @grit, creator: @johndoe, state: "success")
    refute status.commit_oid
    status.save!
    assert status.commit_oid
    assert_equal @sha1, status.commit_oid
  end

  test "populates tree_oid field on save" do
    status = Status.new(sha: @sha1, repository: @grit, creator: @johndoe, state: "success")
    refute status.tree_oid
    status.save!
    assert status.tree_oid
    assert_equal @tree1, status.tree_oid
  end

  test "can create multiple statuses per commit oid with protected branches enabled" do
    status = Status.new(sha: @sha1, repository: @grit, creator: @johndoe, state: "success")
    assert status.save
    status = Status.new(sha: @sha1, repository: @grit, creator: @johndoe, state: "success")
    assert status.save
  end

  test "defaults to 'default' context" do
    assert_equal "default", Status.new(sha: @sha1, repository: @grit).context
  end

  test "all states have adjective forms" do
    Status::States.each do |state|
      assert StatusCheckConfig.adjective_state(state), "'#{state}' is missing an adjective state"
    end
  end

  test "disallows saving 'expected' state" do
    status = @grit.statuses.new
    status.state = "expected"
    refute status.valid?
    assert_equal "is not included in the list", status.errors[:state].first
  end

  test "sort statuses by state" do
    s1 = create(:status, sha: @sha1, repository: @grit, state: "error")
    s2 = create(:status, sha: @sha1, repository: @grit, state: "failure")
    s3 = create(:status, sha: @sha1, repository: @grit, state: "pending")
    s4 = create(:status, sha: @sha1, repository: @grit, state: "success")
    assert_equal [s1, s2, s3, s4], [s4, s2, s3, s1].sort_by(&:sort_order)
  end

  test "sort statuses by context and id within state" do
    s1 = create(:status, sha: @sha1, repository: @grit, state: "success", context: "a")
    s2 = create(:status, sha: @sha1, repository: @grit, state: "success", context: "a")
    s3 = create(:status, sha: @sha1, repository: @grit, state: "success", context: "a")
    s4 = create(:status, sha: @sha1, repository: @grit, state: "success", context: "b")
    s5 = create(:status, sha: @sha1, repository: @grit, state: "success", context: "c")
    assert_equal [s1, s2, s3, s4, s5], [s4, s5, s2, s3, s1].sort_by(&:sort_order)
  end

  test "disallows empty contexts" do
    status = @grit.statuses.new
    status.context = nil
    status.valid?
    assert_equal "can't be blank", status.errors[:context].first
  end

  test "excessively long statuses are invalid" do
    long_context = "a" * 300
    status = build :status, repository: @grit, context: long_context
    refute status.valid?
    assert_equal "is too long (maximum is 255 characters)", status.errors[:context].first
  end

  test "excessively long target_urls are invalid" do
    long_target_url = "https://example.com/#{'a' * MYSQL_TEXT_FIELD_LIMIT}"
    status = build :status, repository: @grit, context: "a", creator: @johndoe, target_url: long_target_url
    refute status.valid?
    assert_equal "is too long (maximum is 16383 characters)", status.errors[:target_url].first
  end

  test "denormalize commit tree sha" do
    skip
    status = create :status, sha: @sha1, state: "success", creator: @johndoe, repository: @grit
    assert_equal @tree1, status.tree_sha
  end

  test "creating a good statuses for the same sha" do
    create :status, sha: @sha1, state: "success", creator: @johndoe, repository: @grit
    create :status, sha: @sha1, state: "failure", creator: @johndoe, repository: @grit
  end

  test "marks statuses with invalid shas as invalid" do
    invalid_oids = ["abcd", "z" * 40, "xxx  " * 8]
    invalid_oids.each do |oid|
      status = build :status, sha: oid
      assert !status.valid?
      assert_equal "must be a valid hex object ID", status.errors[:sha].first
    end
  end

  test "cannot create more statuses per sha, context, repo than the limit" do
    Status.stub_const(:MAX_PER_SHA_AND_CONTEXT, 5) do # avoid creating a ton of objects
      5.times do |_i|
        create :status, sha: @sha1, state: "failure", repository: @grit
      end
      status = build :status, sha: @sha1, repository: @grit, creator: @johndoe
      assert status.invalid?
      assert_equal ["This SHA and context has reached the maximum number of statuses."], status.errors[:base]
    end
  end

  test "limitation does not apply across contexts" do
    Status.stub_const(:MAX_PER_SHA_AND_CONTEXT, 5) do # avoid creating a ton of objects
      10.times do |i|
        create :status, sha: @sha1, state: "failure", repository: @grit, context: "context #{i}"
      end
      assert_equal 10, Status.where(sha: @sha1, repository_id: @grit).count
    end
  end

  test "high unicode in description is invalid" do
    native_emoji_string = "Grin #{GRIN_EMOJI} Emoji"
    status = build(:status, description: native_emoji_string, repository: @grit, sha: @sha1, creator: @johndoe)
    refute status.valid?, "status should be invalid due to high unicode in the description"
    assert_equal ["doesn't accept 4-byte Unicode"], status.errors[:description]
  end

  test "fetching a referenced commit" do
    status1 = create :status, sha: @sha1, state: "success", creator: @johndoe, repository: @grit
    commit = status1.commit
    assert commit
    assert_equal "Chris Wanstrath", commit.author_name
  end

  test "returns the previous state" do
    status1 = create :status, sha: @sha1, state: "pending", creator: @johndoe, repository: @grit
    status2 = create :status, sha: @sha1, state: "success", creator: @johndoe, repository: @grit
    assert_nil status1.previous_state
    assert_equal "pending", status2.previous_state
  end

  context "branches" do
    test "returns default branch first for merged SHAs" do
      status = create :status, sha: @sha1, state: "success", creator: @johndoe, repository: @grit
      assert_equal "master", status.branches.first
      assert_equal status.repository.rpc.branch_contains(@sha1).length, status.branches.length
    end

    test "returns all matching branches for unmerged SHAs" do
      status = create :status, sha: @sha2, state: "success", creator: @johndoe, repository: @grit
      assert_equal ["blank_lines", "lazy_delegator", "unMERGED-branch-2", "unmerged-branch-1", "籠の鳥".b, "裁き".b], status.branches
    end
  end

  context "required_for_pull_request" do
    test "false if protected branches is not enabled" do
      pull = make_pull_request
      status = build :status, sha: @sha2, state: "success", creator: @johndoe, repository: pull.repository
      refute status.required_for_pull_request?(pull)
    end

    test "true for a status on a protected branch with required status context" do
      pull = make_pull_request
      repo = pull.repository
      ref = repo.heads.find("master")

      protected_branch = create(:protected_branch, repository: repo, name: "master", required_status_checks_enforcement_level: :everyone)
      protected_branch.replace_status_contexts("ci")
      status = create :status, context: "ci", sha: ref.target_oid, state: "success", creator: @johndoe, repository: repo
      assert status.required_for_pull_request?(pull)
    end
  end

  context "combined status helper" do
    test "offers an combined status helper on repository" do
      assert_equal "pending", @grit.combined_status(@sha1).state
    end

    test "takes a ref as well as a sha" do
      assert_equal "pending", @grit.combined_status("master").state
    end

    test "returns nil for non-existent branches" do
      assert_nil @grit.combined_status("oogabooga")
    end
  end

  test "CombinedStatus#combined_statuses_for_shas" do
    create :status, sha: @sha1, state: "failure", creator: @johndoe, repository: @grit, context: "test context"
    status1 = create :status, sha: @sha1, state: "failure", creator: @johndoe, repository: @grit, context: "test context"
    status2 = create :status, sha: @sha1, state: "pending", creator: @johndoe, repository: @grit, context: "test context 2"

    create :status, sha: @sha2, state: "failure", creator: @johndoe, repository: @grit, context: "test context"
    status3 = create :status, sha: @sha2, state: "failure", creator: @johndoe, repository: @grit, context: "test context"
    status4 = create :status, sha: @sha2, state: "pending", creator: @johndoe, repository: @grit, context: "test context 2"

    # No statuses attached to @sha3. We should return an empty combined status for it.
    combined_statuses = CombinedStatus.combined_statuses_for_shas(@grit, [@sha1, @sha2, @sha3])
    assert_equal Set.new([status1, status2]), Set.new(combined_statuses.fetch(@sha1).status_checks)
    assert_equal Set.new([status3, status4]), Set.new(combined_statuses.fetch(@sha2).status_checks)
    refute combined_statuses.fetch(@sha3).any?
  end

  context "#integration" do
    test "returns an Integration for a status created by a Bot" do
      integration = create(:integration, name: "super-ci")

      make_integration_installation(
        integration: integration,
        target: @johndoe,
        permissions: { "statuses" => :write })

      status = create(:status, sha: @sha1, repository: @grit, creator: integration.bot, state: "success")
      assert status.valid?

      assert_equal integration, status.integration
    end

    test "returns nil for a status created by a User" do
      status = create(:status, sha: @sha1, repository: @grit, creator: @johndoe, state: "success")
      assert status.valid?

      assert_nil status.integration
    end
  end

  test "it satisfies the interface required by StatusCheckRollup" do
    StatusCheckRollup::REQUIRED_DUCK_TYPE_METHODS.each do |method|
      assert Status.new.respond_to?(method), "Expected Status to respond to #{method.inspect} to satisfy the duck type for StatusCheckRollup"
    end
  end

  test "#contextual_name" do
    status = create :status, sha: @sha1, state: "failure", creator: @johndoe, repository: @grit, context: "test context"
    assert_equal "test context", status.contextual_name
  end

  test "strips context of extra whitespace" do
    status = create :status, sha: @sha1, state: "success", creator: @johndoe, repository: @grit, context: "\n\ttest extra whitespace is ok  "
    assert_equal "test extra whitespace is ok", status.contextual_name
  end

  context "call auto-merge job enqueuer" do
    test "does nothing if not successful" do
      pull = make_pull_request
      status = build :status, sha: pull.head_sha, state: "failure", creator: @johndoe, repository: pull.repository
      assert status.related_pull_requests.size > 0, "status has no associated pull requests, setup is wrong"

      status.related_pull_requests.each do |pull|
        pull.expects(:enqueue_auto_merge_job_if_enabled).times(0)
        status.call_auto_merge_job_enqueuer
      end
    end

    test "calls enqueue_auto_merge_job_if_enabled on each pull request related to a status" do

      pull = make_pull_request
      status = build :status, sha: pull.head_sha, state: "success", creator: @johndoe, repository: pull.repository
      assert status.related_pull_requests.size > 0, "status has no associated pull requests, setup is wrong"

      status.related_pull_requests.each do |pull|
        pull.expects(:enqueue_auto_merge_job_if_enabled).once
        status.call_auto_merge_job_enqueuer
      end
    end
  end
end
