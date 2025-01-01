# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class PullRequestSerializersTest < Api::SerializerTestCase
  fixtures do
    @ari = create(:user, login: "ari")
    @source = create(:repository, owner: @ari, from_example: :pull_request_source)
    @bwalsh = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @bwalsh, fork_repo: @source, from_example: :pull_request_fork)

    @issue = create(:issue, user: @bwalsh, repository: @source)
    @pull1 = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)
  end

  setup do
    reset_repo_root
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    @pull1.create_merge_commit
    @pull1.reload
  end

  context "mergeability related data" do
    test "default (i.e. non-full) output does not include merge info" do
      output = serialize_hash_method(:pull_request_hash, @pull1)
      merge_related_keys = %w[merged mergeable mergeable_state merged_by maintainer_can_modify]
      merge_related_keys.each do |key|
        refute output.key?(key), "output should not have a #{key.inspect} key"
      end
    end

    test "full ouptut reports correct info" do
      output = serialize_hash_method(:pull_request_hash, @pull1, full: true)
      assert_equal false, output["merged"]
      assert_equal true, output["mergeable"]
      assert_equal "clean", output["mergeable_state"]
      assert_equal false, output["maintainer_can_modify"]
      assert_nil output["merged_by"]
    end

    test "includes required review info when version header is present" do
      api_media_type "application/vnd.github.night-shift"
      output = serialize_hash_method(:pull_request_hash, @pull1)

      requirements = output["mergeability_requirements"]["required_reviews"]
      assert_equal true, requirements.fetch("fulfilled")
      assert_nil requirements.fetch("summary")
      assert_nil requirements.fetch("message")
    end

    test "includes reasons when merging is blocked" do
      create(
        :protected_branch,
        name: "master",
        repository: @source,
        creator: @ari,
        pull_request_reviews_enforcement_level: :everyone,
        required_status_checks_enforcement_level: :non_admins,
      )
      pull = PullRequest.create_for!(
        @source,
        base: "master",
        head: "master-forward-2",
        user: @ari,
        title: "this PR is not mergeable",
        body: "needs review",
      )

      api_media_type "application/vnd.github.night-shift"

      output = serialize_hash_method(:pull_request_hash, @pull1)

      requirements = output["mergeability_requirements"]["required_reviews"]
      assert_equal false, requirements["fulfilled"]
      assert_equal "Review required", requirements["summary"]
      assert_equal "At least 1 approving review is required by reviewers with write access.", requirements["message"]
    end

    test "does not include mergeability requirements when header is absent" do
      output = serialize_hash_method(:pull_request_hash, @pull1)

      refute output.key?("mergeability_requirements")
    end
  end

  context "minimal_pull_request_hash" do
    test "includes pull request number" do
      output = serialize_hash_method(:minimal_pull_request_hash, @pull1)
      assert_equal @pull1.number, output["number"]
    end
  end

  context "#pull_request_hash" do
    test "payload is valid" do
      output = serialize_hash_method(:pull_request_hash, @pull1)
      assert output.key?("url")
      assert output.key?("id")
      assert output.key?("title")
      assert output.key?("body")
    end

    test "payload with issue lock reason is valid" do
      valid_reason = Issue::LOCK_REASONS.first
      @pull1.issue.lock(@ari, valid_reason)

      output = serialize_hash_method(:pull_request_hash, @pull1)

      assert output["locked"]
      assert_equal valid_reason, output["active_lock_reason"]
    end

    test "payload includes minimal repo info with repo_identifier_only option" do
      output = serialize_hash_method(:pull_request_hash, @pull1, repo_identifier_only: true)
      assert_equal @pull1.head_repository.id, output["head"]["repo"]["id"]
      assert_nil output["head"]["repo"]["default_branch"]
      assert_nil output["base"]["repo"]["default_branch"]
    end
  end

  context "pull_request_diff_stats_hash" do
    test "payload is valid" do
      output = serialize_hash_method(:pull_request_hash, @pull1, full: true)
      assert_operator output["commits"], :>, 0
      assert_operator output["changed_files"], :>, 0
    end

    test "rescues CommandFailed errors" do
      @pull1.stubs(:async_changed_commits).raises(Repository::CommandFailed.new("failed"))
      output = serialize_hash_method(:pull_request_hash, @pull1, full: true)

      assert_equal output["commits"], 0
      assert_equal output["additions"], 0
      assert_equal output["deletions"], 0
      assert_equal output["changed_files"], 0
    end

    test "rescues invalid diff comparisons" do
      @pull1.update(head_sha: "invalid_head_sha")
      output = serialize_hash_method(:pull_request_hash, @pull1, full: true)

      assert_equal output["commits"], 0
      assert_equal output["additions"], 0
      assert_equal output["deletions"], 0
      assert_equal output["changed_files"], 0
    end
  end

  context "auto_merge" do
    test "object is included when enabled" do
      @source.allow_auto_merge(actor: @ari)
      @pull1.reload
      @pull1.mergeable = false
      @source.protect_branch(@pull1.base_ref, creator: @ari, required_pull_request_reviews: { require_code_owner_reviews: true }, entry_point: :test_case)

      auto_merge_request = AutoMergeRequest.create!(
        pull_request: @pull1,
        user: @ari,
        merge_method: :auto_squash_and_merge,
        commit_title: "Commit title",
        commit_message: "Commit message"
      )

      output = serialize_hash_method(:pull_request_hash, @pull1)

      assert_equal @ari.id, output["auto_merge"]["enabled_by"]["id"]
      assert_equal "squash", output["auto_merge"]["merge_method"]
      assert_equal "Commit title", output["auto_merge"]["commit_title"]
      assert_equal "Commit message", output["auto_merge"]["commit_message"]
    end

    test "is nil when disabled" do
      assert_nil @pull1.auto_merge_request
      output = serialize_hash_method(:pull_request_hash, @pull1)

      assert_nil output["auto_merge"]
    end
  end
end
