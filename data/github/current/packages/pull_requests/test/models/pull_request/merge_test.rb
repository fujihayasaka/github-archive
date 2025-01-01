# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestMergeTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:user, login: "ari")
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @issue = create(:issue, user: @forker, repository: @source)
    @pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    reset_repo_root
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    WebFlowHelper.setup_webflow
  end

  context "#perform" do
    context "for a merge" do
      test "fails when not prepared and no merge commit provided" do
        merger = PullRequest::Merge.new(@pull, :merge, @owner)
        assert_raises { merger.perform }
      end

      test "succeeds when prepared and no merge commit provided" do
        merger = PullRequest::Merge.new(@pull, :merge, @owner)
        prepare_result = merger.prepare_and_validate
        assert_equal true, prepare_result.success

        merge_result = merger.perform
        assert_instance_of PullRequest::Merge::ValidateSuccessResult, prepare_result
        fail unless prepare_result.is_a?(PullRequest::Merge::ValidateSuccessResult)
        assert_equal true, prepare_result.success

        final_merge_commit = @source.commits.find(merge_result.new_sha)
        refute_nil final_merge_commit

        assert_equal prepare_result.merge_commit.tree_oid, final_merge_commit.tree_oid
        assert_equal prepare_result.merge_commit.parent_oids, final_merge_commit.parent_oids
      end

      test "returns the final merge commit id" do
        mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
        assert_equal true, mergeable

        temp_merge_commit = @source.commits.find(temp_merge_commit_id)
        merger = PullRequest::Merge.new(@pull, :merge, @owner, merge_commit: temp_merge_commit)
        result = merger.perform
        assert_equal true, result.success

        final_merge_commit = @source.commits.find(result.new_sha)
        refute_nil final_merge_commit

        assert_equal temp_merge_commit.tree_oid, final_merge_commit.tree_oid
        assert_equal temp_merge_commit.parent_oids, final_merge_commit.parent_oids
      end

      test "sets the merge commit author to the actor" do
        mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
        assert_equal true, mergeable

        temp_merge_commit = @source.commits.find(temp_merge_commit_id)
        merger = PullRequest::Merge.new(@pull, :merge, @owner, merge_commit: temp_merge_commit)
        result = merger.perform
        assert_equal true, result.success

        final_merge_commit = @source.commits.find(result.new_sha)
        refute_nil final_merge_commit

        assert_equal @owner.git_author_name, final_merge_commit.author_name
        assert_equal @owner.git_author_email, final_merge_commit.author_email
      end

      if GitHub.choose_commit_email_enabled?
        test "allows a custom author email to be used" do
          mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
          assert_equal true, mergeable

          custom_author_email = @owner.add_email("new@example.com")
          @owner.emails.each(&:verify!)
          custom_author_email = custom_author_email.email

          temp_merge_commit = @source.commits.find(temp_merge_commit_id)
          merger = PullRequest::Merge.new(
            @pull, :merge, @owner, merge_commit: temp_merge_commit, author_email: custom_author_email
          )
          result = merger.perform
          assert_equal true, result.success

          final_merge_commit = @source.commits.find(result.new_sha)
          refute_nil final_merge_commit

          assert_equal @owner.git_author_name, final_merge_commit.author_name
          assert_equal custom_author_email, final_merge_commit.author_email
        end
      else
        test "does not allow a custom author email to be used", skip_enterprise: true do
          mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
          assert_equal true, mergeable

          custom_author_email = @owner.add_email("new@example.com")
          @owner.emails.each(&:verify!)
          custom_author_email = custom_author_email.email

          temp_merge_commit = @source.commits.find(temp_merge_commit_id)
          assert_raises do
            PullRequest::Merge.new(
              @pull, :merge, @owner, merge_commit: temp_merge_commit, author_email: custom_author_email
            )
          end
        end
      end

      test "fails when the pull request is a draft" do
        repo = create(:repository, owner: @owner, from_example: :pull_request_source)
        head_ref = repo.heads.create("topic", repo.heads.find("master").target, @owner)
        head_ref.append_commit({ message: "a change", committer: @owner }, @owner) do |files|
          files.add("README.txt", "one\ntwo\nthree\n")
        end
        pull = create(:pull_request, repository: repo, base_repository: repo, base_user: @owner,
                      base_ref: "master", head_repository: repo, head_user: @owner,
                      head_ref: "topic", user: @owner, draft: true)
        merge_commit_id = pull.create_merge_commit
        refute_nil merge_commit_id
        merge_commit = repo.commits.find(merge_commit_id)
        merger = PullRequest::Merge.new(pull, :merge, @owner, merge_commit: merge_commit)

        result = merger.perform

        assert_equal false, result.success
      end

      test "sets the merge commit committer to the GitHub web committer" do
        mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
        assert_equal true, mergeable

        temp_merge_commit = @source.commits.find(temp_merge_commit_id)
        merger = PullRequest::Merge.new(@pull, :merge, @owner, merge_commit: temp_merge_commit)
        result = merger.perform
        assert_equal true, result.success

        final_merge_commit = @source.commits.find(result.new_sha)
        refute_nil final_merge_commit

        assert_equal GitHub.web_committer_name, final_merge_commit.committer_name
        assert_equal GitHub.web_committer_email, final_merge_commit.committer_email
      end

      test "doesn't perform a rebase when no merge commit provided" do
        GitRPC::Client.any_instance.expects(
          GitHub.flipper[:tmp_objdir_experiment].enabled?(@repository) ? :rebase_tmp_objdir_experiment : :rebase
        ).never

        merger = PullRequest::Merge.new(@pull, :merge, @owner)
        prepare_result = merger.prepare_and_validate
        assert_instance_of PullRequest::Merge::ValidateSuccessResult, prepare_result
        fail unless prepare_result.is_a?(PullRequest::Merge::ValidateSuccessResult)
        assert_equal true, prepare_result.success

        merge_result = merger.perform
        assert_equal true, merge_result.success

        final_merge_commit = @source.commits.find(merge_result.new_sha)
        refute_nil final_merge_commit

        assert_equal prepare_result.merge_commit.tree_oid, final_merge_commit.tree_oid
        assert_equal prepare_result.merge_commit.parent_oids, final_merge_commit.parent_oids
      end
    end

    context "for a squash" do
      test "returns the final squash commit id" do
        mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
        assert_equal true, mergeable

        temp_merge_commit = @source.commits.find(temp_merge_commit_id)
        merger = PullRequest::Merge.new(@pull, :squash, @owner, merge_commit: temp_merge_commit)
        result = merger.perform
        assert_equal true, result.success

        final_squash_commit = @source.commits.find(result.new_sha)

        assert_equal temp_merge_commit.tree_oid, final_squash_commit.tree_oid
        assert_equal [temp_merge_commit.parent_oids[0]], final_squash_commit.parent_oids
      end

      test "doesn't perform a rebase when no merge commit provided" do
        GitRPC::Client.any_instance.expects(
          GitHub.flipper[:tmp_objdir_experiment].enabled?(@repository) ? :rebase_tmp_objdir_experiment : :rebase
        ).never

        merger = PullRequest::Merge.new(@pull, :squash, @owner)
        prepare_result = merger.prepare_and_validate

        assert_instance_of PullRequest::Merge::ValidateSuccessResult, prepare_result
        fail unless prepare_result.is_a?(PullRequest::Merge::ValidateSuccessResult)
        assert_equal true, prepare_result.success

        merge_result = merger.perform
        assert_instance_of PullRequest::Merge::PerformSuccessResult, merge_result
        fail unless merge_result.is_a?(PullRequest::Merge::PerformSuccessResult)
        assert_equal true, merge_result.success

        final_squash_commit = @source.commits.find(merge_result.new_sha)
        refute_nil final_squash_commit

        assert_equal prepare_result.merge_commit.tree_oid, final_squash_commit.tree_oid
        assert_equal [prepare_result.merge_commit.parent_oids[0]], final_squash_commit.parent_oids
      end
    end

    context "for a rebase" do
      test "returns the rebased head commit id" do
        mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
        assert_equal true, mergeable

        temp_merge_commit = @source.commits.find(temp_merge_commit_id)
        merger = PullRequest::Merge.new(@pull, :rebase, @owner, merge_commit: temp_merge_commit)
        result = merger.perform
        assert_equal true, result.success

        original_commits = @pull.comparison.commits

        # We have 3 initial commits here, but only 2 of those get reapplied.
        # The contents of the third commit is already included in the base branch,
        # and so it gets dropped.
        assert_equal 3, original_commits.size

        c = @source.commits.find(result.new_sha)
        # Commit id changes, tree id is stable
        assert_equal "931244c2872cd67049d710a288b6361c0289fe96", c.tree_oid

        c = @source.commits.find(c.parent_oids[0])
        # Commit id changes, tree id is stable
        assert_equal "84a3d27e743a9a8504002752cd452d864c2ed0bc", c.tree_oid

        assert_equal [temp_merge_commit.parent_oids[0]], c.parent_oids
      end
    end

    test "preparing a pull request doesn't trigger custom hooks" do
      Repository.any_instance.expects(:check_custom_hooks).with do |_old_oid, _new_oid, _qualified_name, options|
        options[:no_custom_hooks] == true
      end.times(2)

      mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
    end

    test "runs custom hooks on writing internal rebase ref (but not when preparing the PR)" do
      Repository.any_instance.expects(:check_custom_hooks).with do |_old_oid, _new_oid, _qualified_name, options|
        options[:no_custom_hooks] == true
      end.times(2)

      mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal true, mergeable

      Repository.any_instance.expects(:check_custom_hooks).with do |_old_oid, _new_oid, _qualified_name, options|
        options[:no_custom_hooks] == false
      end
      temp_merge_commit = @source.commits.find(temp_merge_commit_id)
      merger = PullRequest::Merge.new(@pull, :rebase, @owner, merge_commit: temp_merge_commit)
      result = merger.perform
      assert_equal true, result.success
    end
  end

  context "commit signing" do
    context "for a squash" do
      test "signs commit if merger is author" do
        @source.add_member(@forker)

        mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
        temp_merge_commit = @source.commits.find(temp_merge_commit_id)
        merger = PullRequest::Merge.new(@pull, :squash, @forker, merge_commit: temp_merge_commit)
        result = merger.perform
        assert_equal true, result.success

        final_squash_commit = @source.commits.find(result.new_sha)
        refute_nil final_squash_commit
        assert final_squash_commit.has_signature?, "squash commit is not signed"
        assert final_squash_commit.signed_by_github?, "squash commit is not signed by GitHub"
        assert final_squash_commit.verified_signature?, "signature is not verified"
      end

      test "signs commit if merger isn't author" do
        mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
        temp_merge_commit = @source.commits.find(temp_merge_commit_id)
        merger = PullRequest::Merge.new(@pull, :squash, @owner, merge_commit: temp_merge_commit)
        result = merger.perform
        assert_equal true, result.success

        final_squash_commit = @source.commits.find(result.new_sha)
        refute_nil final_squash_commit
        assert final_squash_commit.has_signature?, "squash commit is not signed"
        assert final_squash_commit.signed_by_github?, "squash commit is not signed by GitHub"
        assert final_squash_commit.verified_signature?, "signature is not verified"
      end

      test "commit signing error handling" do
        GitHub.gpg.stubs(:sign).raises(GpgVerify::EarthsmokeError)
        @source.add_member(@forker)

        mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
        temp_merge_commit = @source.commits.find(temp_merge_commit_id)

        merger = PullRequest::Merge.new(@pull, :squash, @forker, merge_commit: temp_merge_commit)
        result = merger.perform
        assert_equal true, result.success

        final_squash_commit = @source.commits.find(result.new_sha)
        refute_nil final_squash_commit
        refute_predicate final_squash_commit, :has_signature?
      end
    end

    context "for a merge" do
      test "signs commit" do
        mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
        temp_merge_commit = @source.commits.find(temp_merge_commit_id)
        merger = PullRequest::Merge.new(@pull, :merge, @owner, merge_commit: temp_merge_commit)
        result = merger.perform
        assert_equal true, result.success

        final_merge_commit = @source.commits.find(result.new_sha)
        refute_nil final_merge_commit
        assert_predicate final_merge_commit, :verified_signature?
      end

      test "commit signing error handling" do
        GitHub.gpg.stubs(:sign).raises(GpgVerify::EarthsmokeError)
        mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
        temp_merge_commit = @source.commits.find(temp_merge_commit_id)
        merger = PullRequest::Merge.new(@pull, :merge, @owner, merge_commit: temp_merge_commit)
        result = merger.perform
        assert_equal true, result.success

        final_merge_commit = @source.commits.find(result.new_sha)
        refute_nil final_merge_commit
        refute_predicate final_merge_commit, :has_signature?
      end

      test "fails when protected branch requires signed commit and we cannnot sign" do
        Repository.any_instance.stubs(:disable_libgit2_to_git_experiments).returns(true)
        create(:protected_branch,
          repository: @source,
          name: "master",
          required_status_checks_enforcement_level: :off,
          pull_request_reviews_enforcement_level: :off,
          signature_requirement_enforcement_level: :everyone,
        )

        GitHub.gpg.expects(:sign).twice.raises(GpgVerify::Unavailable)

        mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
        temp_merge_commit = @source.commits.find(temp_merge_commit_id)
        merger = PullRequest::Merge.new(@pull, :merge, @owner, merge_commit: temp_merge_commit)
        result = merger.perform

        assert_instance_of PullRequest::Merge::FailResult, result
        fail unless result.is_a?(PullRequest::Merge::FailResult)

        assert_equal false, result.success
        assert_match /branch requires that commits be signed/, result.fail_message
        assert_equal :protected_branch, result.fail_code
      end

      test "succeeds when protected branch requires signed commit and we can sign" do
        create(:protected_branch,
          repository: @source,
          name: "master",
          required_status_checks_enforcement_level: :off,
          pull_request_reviews_enforcement_level: :off,
          signature_requirement_enforcement_level: :everyone,
        )

        mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
        temp_merge_commit = @source.commits.find(temp_merge_commit_id)
        merger = PullRequest::Merge.new(@pull, :merge, @owner, merge_commit: temp_merge_commit)
        result = merger.perform
        assert_equal true, result.success

        final_merge_commit = @source.commits.find(result.new_sha)
        refute_nil final_merge_commit
        assert_predicate final_merge_commit, :verified_signature?
      end
    end
  end if GitHub.web_commit_signing_enabled?

  context "#post_merge" do
    test "pull request is marked as merged" do
      _, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      temp_merge_commit = @source.commits.find(temp_merge_commit_id)
      merger = PullRequest::Merge.new(@pull, :merge, @owner, merge_commit: temp_merge_commit)
      result = merger.perform
      assert_equal true, result.success

      final_merge_commit = @source.commits.find(result.new_sha)
      merger.post_merge(final_merge_commit, @pull.base, result.new_sha, Time.now, :direct_merge, enqueue_push_job: false)

      refute_nil @pull.merged_at
      assert_equal @pull.merge_commit_sha, result.new_sha
      assert_nil @pull.mergeable
    end

    test "referenced issues are close upon merge" do
      _, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      temp_merge_commit = @source.commits.find(temp_merge_commit_id)
      merger = PullRequest::Merge.new(@pull, :merge, @owner, merge_commit: temp_merge_commit)
      result = merger.perform
      assert_equal true, result.success

      final_merge_commit = @source.commits.find(result.new_sha)

      assert_performed_with job: PullRequestCloseReferencedIssuesJob do
        merger.post_merge(final_merge_commit, @pull.base, result.new_sha, Time.now, :direct_merge, enqueue_push_job: false)
      end
    end

    test "kicks off push processing" do
      _, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      temp_merge_commit = @source.commits.find(temp_merge_commit_id)
      merger = PullRequest::Merge.new(@pull, :merge, @owner, merge_commit: temp_merge_commit)
      result = merger.perform
      assert_equal true, result.success

      final_merge_commit = @source.commits.find(result.new_sha)
      merge_base_ref = @pull.repository.refs.read("master")

      merger.post_merge(final_merge_commit, merge_base_ref, result.new_sha, Time.now, :direct_merge)
      with_hydro_publisher(GitHub.sync_hydro_publisher) { assert_hydro_messages(count: 1, schema: "github.repositories.v1.Pushed") }
    end

    context "record_post_merge_metrics" do
      test "instruments a pull_request.merge event" do
        _, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
        temp_merge_commit = @source.commits.find(temp_merge_commit_id)
        merger = PullRequest::Merge.new(@pull, :merge, @owner, merge_commit: temp_merge_commit)
        result = merger.perform
        assert_equal true, result.success

        events = subscribe "pull_request.merge"

        final_merge_commit = @source.commits.find(result.new_sha)
        merger.post_merge(final_merge_commit, @pull.base, result.new_sha, Time.now, :direct_merge, enqueue_push_job: false)

        assert event = events.pop, "expected an instrumention event"
        assert_equal "pull_request.merge", event.name
      end

      test "increments merge stats" do
        _, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
        temp_merge_commit = @source.commits.find(temp_merge_commit_id)
        merger = PullRequest::Merge.new(@pull, :merge, @owner, merge_commit: temp_merge_commit)
        result = merger.perform
        assert_equal true, result.success

        final_merge_commit = @source.commits.find(result.new_sha)

        assert_difference -> {
          GitHub.dogstats.increments("pull_request", tags: ["action:merged", "result:merge"]).length
        }, 1 do
          merger.post_merge(final_merge_commit, @pull.base, result.new_sha, Time.now, :direct_merge, enqueue_push_job: false)
        end
      end
    end

  end
end
