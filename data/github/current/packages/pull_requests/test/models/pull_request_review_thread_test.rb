# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewThreadTest < GitHub::TestCase
  include HydroTestHelpers
  include PlatformTestHelpers::InterfaceHelpers
  include PullRequestSynchronizationTestHelpers

  fixtures do
    @owner = create(:user)
    @viewer = create(:user)
    @site_admin = create(:staff_admin_user)
    @repo = create(:repository, owner: @owner)
    @issue = create(:issue, repository: @repo)
  end

  setup do
    example_repo :simple, @repo

    master = @repo.heads.find("master")
    master.append_commit({ message: "adding a file", committer: @repo.owner }, @repo.owner) do |files|
      files.add("readme.txt", "oh hey")
    end

    @ref = @repo.heads.create("topic", @repo.heads.find("master").target, @repo.owner)
    @commit = @ref.append_commit({ message: "Add file1", committer: @repo.owner }, @repo.owner) do |files|
      files.add("file1.txt", "line1\nline2\nline3\n")
      files.add("file2.txt", "line1\nline2\nline3\n")
      files.add("original_file_name.txt", "line1\nline2\nline3\n")
      files.add("rename_me.txt", "hey hey hey")
      files.move("a", "renamed.txt", "a\nb\nc\n")
      files.move("empty_file", "renamed_empty_file", "")
      files.remove("readme.txt")
    end

    @ref.append_commit({ message: "Delete file2", committer: @repo.owner }, @repo.owner) do |files|
      files.remove("file2.txt")
      files.move("renamed.txt", "a", "a\nb\nc\n")
      files.move("rename_me.txt", "heyheyhey.txt", "hey hey hey")
      files.move("original_file_name.txt", "temp_rename.txt", "line1\nline2\nline3")
    end

    @ref.append_commit({ message: "rename temp_rename back", committer: @repo.owner }, @repo.owner) do |files|
      files.move("temp_rename.txt", "original_file_name.txt", "line1\nline2\nline3")
    end

    @pull = PullRequest.create_for(
      @repo,
      base: "master",
      head: @ref.name,
      user: @owner,
      issue: @issue,
    )

    user = create(:user)
    blocked_user = create(:user)

    @legacy_thread = create_legacy_thread
    @spammy_legacy_thread = create_legacy_thread(user: create(:user, spammy: true))
    @unsubmitted_legacy_thread = create_legacy_thread(submit: false, user: @owner)
    @blocked_legacy_thread = create_legacy_thread(user: blocked_user)

    @owner.block(blocked_user)
    example_repo_snapshot

    example_repo_restore

    Spokesd.enable_spokesd
  end

  def create_legacy_thread(user: create(:user), submit: true)
    review = @pull.pending_review_for(user: user, head_sha: @pull.head_sha)

    thread = review.build_thread(
      commit_id: @pull.head_sha,
      path: "file1.txt",
      original_position: 1,
    )
    thread.save!

    comment = create(:pull_request_review_comment,
      body: "just commented",
      user: user,
      pull_request_id: @pull.id,
      pull_request_review_id: nil,
      pull_request_review_thread: thread,
      reply_to_id: nil,
    )
    comment.submit! if submit

    # legacy threads have no review
    thread.update_column(:pull_request_review_id, nil)
    thread.reload

    thread
  end

  def callback_count_message(callback_type_name, from_count, to_count, base_message)
    "Callback count changed for #{callback_type_name} callbacks on the PullRequestReviewThread model from #{from_count} to #{to_count}. \n#{base_message}"
  end

  context ".visible_to" do
    if GitHub.spamminess_check_enabled?
      test "returns visible threads for timeline of anonymous user" do
        threads = PullRequestReviewThread.visible_to(nil)
        assert_same_elements [@legacy_thread, @blocked_legacy_thread], threads
      end

      test "returns visible threads for timeline of user" do
        threads = PullRequestReviewThread.visible_to(@viewer)
        assert_same_elements [@legacy_thread, @blocked_legacy_thread], threads
      end

      test "returns unsubmitted threads for timeline of comment author" do
        threads = PullRequestReviewThread.visible_to(@owner)
        assert_same_elements [@legacy_thread, @unsubmitted_legacy_thread, @blocked_legacy_thread], threads
      end
    else
      test "returns visible threads for timeline of anonymous user" do
        threads = PullRequestReviewThread.visible_to(nil)
        assert_same_elements [@legacy_thread, @spammy_legacy_thread, @blocked_legacy_thread], threads
      end

      test "returns visible threads for timeline of user" do
        threads = PullRequestReviewThread.visible_to(@viewer)
        assert_same_elements [@legacy_thread, @spammy_legacy_thread, @blocked_legacy_thread], threads
      end

      test "returns unsubmitted threads for timeline of comment author" do
        threads = PullRequestReviewThread.visible_to(@owner)
        assert_same_elements [@legacy_thread, @spammy_legacy_thread, @unsubmitted_legacy_thread, @blocked_legacy_thread], threads
      end
    end

    test "returns visible threads for timeline of site admin" do
      threads = PullRequestReviewThread.visible_to(@site_admin)
      assert_same_elements [@legacy_thread, @spammy_legacy_thread, @blocked_legacy_thread], threads
    end
  end

  test "#async_pull_request_commit" do
    @base = create(:repository, from_example: :review_comment_source)
    @head = create(:fork_repository, forker: create(:user), fork_repo: @base, from_example: :review_comment_fork)

    @pull = PullRequest.create_for(@base,
      user:  @head.owner,
      base:  "master",
      head:  "#{@head.owner}:topic",
      title: "some title",
      body:  "some body",
    )

    @review = @pull.pending_review_for(user: @base.owner)
    thread1 = @review.build_thread
    @comment1 = thread1.build_first_comment(
      body: "text",
      path: "aquaman.txt",
      line: 5,
      side: :left,
    )

    thread2 = @review.build_thread
    @comment2 = thread2.build_first_comment(
      body: "more text",
      path: "aquaman.txt",
      line: 11,
    )

    @review.save
    thread1.save
    thread2.save

    # merge base for topic
    assert_equal "564af74a07da170ec3a45ef0a8cc34e8a8c1aa89", thread1.async_pull_request_commit.sync.commit.oid

    assert_equal @head.heads.find("topic").target_oid, thread2.async_pull_request_commit.sync.commit.oid
  end

  test "single line thread has start and end lines" do
    assert_equal 1, @legacy_thread.async_start_line.sync.current
    assert_equal 1, @legacy_thread.async_end_line.sync.current
  end

  context "#safe_line" do
    test "behaves like `#line` with valid data" do
      assert_equal @legacy_thread.safe_line, @legacy_thread.line
    end

    test "gracefully handles invalid data" do
      # Ensure `#async_position_data` will use `LegacyPositionData`
      @legacy_thread.update!(blob_position: nil)
      # Put the record into an invalid state
      @legacy_thread.update_attribute(:compressed_diff_hunk, "")
      # Use a fresh instance to reset any memoization
      thread = PullRequestReviewThread.find(@legacy_thread.id)

      # Verify the test setup: we expect `#line` to raise.
      assert_raises(PullRequestReviewComment::AbstractPositionData::InvalidDiffError) do
        thread.line
      end

      assert_nil(thread.safe_line)
    end
  end

  test "async_adjusted_blob_position will raise or not raise depending on if safe is passed in" do
    # Ensure `#async_position_data` will use `LegacyPositionData`
    @legacy_thread.update!(blob_position: nil)
    # Put the record into an invalid state
    @legacy_thread.update_attribute(:compressed_diff_hunk, "")

    # Use a fresh instance to reset any memoization
    thread = PullRequestReviewThread.find(@legacy_thread.id)

    assert_raises(PullRequestReviewComment::AbstractPositionData::InvalidDiffError) do
      thread.async_adjusted_blob_position.sync
    end
    assert_nothing_raised do
      thread.async_adjusted_blob_position(safe: true).sync
    end
  end


  test "sets `repository_id` from the pull" do
    review_thread = create(:pull_request_review_thread, pull_request: @pull)

    refute_nil review_thread.repository_id
    assert_equal @pull.repository_id, review_thread.repository_id
  end

  test "`repository_id` remains set when PullRequestReviewThreads are deleted" do
    review_thread = create(:pull_request_review_thread, pull_request: @pull)
    refute_nil review_thread.repository_id
    repo = Repositories::Public.find_active!(review_thread.repository_id)
    only = [DestroyDependentRecordsJob, RepositoryOrchestrationJob]
    perform_enqueued_jobs(only: only) do
      @repo.remove(@repo.owner)
    end
    archived_review_thread = PullRequestReviewThread.find(review_thread.id)
    assert_equal @pull.repository_id, archived_review_thread.repository_id
  end

  test "`repository_id` column remains set when a deleted PullRequestReviewThread` is restored" do
    review_thread = create(:pull_request_review_thread, pull_request: @pull)
    refute_nil review_thread.repository_id
    repo = Repositories::Public.find_active!(review_thread.repository_id)
    jobs = [DestroyDependentRecordsJob, RepositoryOrchestrationJob]
    perform_enqueued_jobs(only: jobs) do
      @repo.remove(@repo.owner)
    end
    deleted_repo = Repositories::Public.find_deleted(@repo.id)
    GitRPC::Client.any_instance.stubs(:gitbackups_restore).with do |spec|
      GitHub::GitbackupsTestHelper.restore_from_example(spec)
    end
    Repository.restore(deleted_repo)
    restored_pr_thread = PullRequestReviewThread.find(review_thread.id)
    assert_equal @pull.repository_id, restored_pr_thread.repository_id
  end

  context "audit log" do
    test "instruments pull_request_review_thread.create event" do
      events = subscribe "pull_request_review_thread.create"

      review = create :pull_request_review, pull_request: @pull, user: @viewer
      comment = create :pull_request_review_comment, pull_request: @pull, user: @viewer, pull_request_review: review

      expected_payload = {
        pull_request_review_thread_id: comment.pull_request_review_thread.id,
        repository: @repo.name_with_display_owner,
        repository_id: @repo.id,
        repo: @repo.name_with_display_owner,
        public_repo: @repo.public?,
        pull_request_id: @pull.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments pull_request_review_thread.delete event" do
      events = subscribe "pull_request_review_thread.delete"

      review = create :pull_request_review, pull_request: @pull, user: @viewer
      comment = create :pull_request_review_comment, pull_request: @pull, user: @viewer, pull_request_review: review
      comment.pull_request_review_thread.destroy!

      expected_payload = {
        pull_request_review_thread_id: comment.pull_request_review_thread.id,
        repository: @repo.name_with_display_owner,
        repository_id: @repo.id,
        repo: @repo.name_with_display_owner,
        public_repo: @repo.public?,
        pull_request_id: @pull.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments pull_request_review_thread.resolve event" do
      events = subscribe "pull_request_review_thread.resolve"

      review = create :pull_request_review, pull_request: @pull, user: @viewer
      comment = create :pull_request_review_comment, pull_request: @pull, user: @viewer, pull_request_review: review
      comment.pull_request_review_thread.resolve(resolver: @owner)

      expected_payload = {
        pull_request_review_thread_id: comment.pull_request_review_thread.id,
        repo: @repo.name_with_display_owner,
        pull_request_id: @pull.id,
        resolver_id: @owner.id,
        resolver: @owner.login,
        repository: @repo.name_with_display_owner,
        repository_id: @repo.id,
        public_repo: @repo.public?,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "Publish to Hydro", skip_enterprise: true do
    test "instruments pull_request_review_thread.create hydro event" do
      Timecop.freeze(Time.now) do
        repo = create(:repository, from_example: :pull_request_fork)
        pull = create :pull_request, repository: repo
        review = create :pull_request_review, pull_request: pull, user: @owner
        comment = create :pull_request_review_comment, pull_request: pull, user: @owner, pull_request_review: review

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published({
            pull_request_review_thread: Hydro::EntitySerializer.pull_request_review_thread(comment.pull_request_review_thread),
            repository: Hydro::EntitySerializer.repository(repo),
          }, schema: "github.v1.PullRequestReviewThreadCreate")
        end
      end
    end

    test "instruments pull_request_review_thread.delete hydro event" do
      Timecop.freeze(Time.now) do
        repo = create(:repository, from_example: :pull_request_fork)
        pull = create :pull_request, repository: repo
        review = create :pull_request_review, pull_request: pull, user: @owner
        comment = create :pull_request_review_comment, pull_request: pull, user: @owner, pull_request_review: review

        comment.pull_request_review_thread.destroy!

        assert_hydro_published({
          pull_request_review_thread: Hydro::EntitySerializer.pull_request_review_thread(comment.pull_request_review_thread),
          repository: Hydro::EntitySerializer.repository(repo),
        }, schema: "github.v1.PullRequestReviewThreadDelete")
      end
    end
  end

  context "validations" do
    # File level threads is a special case where we skip
    # `before_validations` calls for setting position related attributes.
    # and as a result we skip validations for file level threads.
    # In order not to repeat the same test specs for diff line threads (the default)
    # we can consider test specs outside of the `file level threads` context
    # are working for all types of threads including `file_level threads`
    # unless we have contrary test specs within the `file level thread` context
    # then we consider these test specs as applicable on other types of threads.

    context "file level thread" do
      test "creating file-level threads using build_first_comment works" do
        comparison = @pull.async_pull_comparison.sync
        review = @pull.pending_review_for(user: @repo.owner)
        thread = review.build_thread(subject_type: :file)
        thread.build_first_comment(
          user: @repo.owner,
          body: "good job!",
          path: "file1.txt",
          diff: comparison.diffs
        )
        review.save!

        assert_predicate thread, :persisted?
      end

      test "creating file-level threads using build_first_diff_position_comment works" do
        comparison = @pull.async_pull_comparison.sync
        review = @pull.pending_review_for(user: @repo.owner)

        thread = review.build_thread(subject_type: :file)
        thread.build_first_diff_position_comment(
          user: @repo.owner,
          body: "good job!",
          path: "file1.txt",
          position: nil,
          diff: comparison.diffs
        )
        review.save!

        assert_predicate thread, :persisted?
      end

      test "valid file level thread has nil values for position attributes" do
        thread = create(:pull_request_review_thread, :on_file, pull_request: @pull)

        assert thread.valid?
        %w(blob_position original_position position start_position_offset).each do |attr|
          assert_nil thread.send(attr)
        end
      end

      test "valid file level thread has values for commit attributes" do
        thread = create(:pull_request_review_thread, :on_file, pull_request: @pull)

        assert thread.valid?
        %w(commit_id original_base_commit_id original_commit_id original_start_commit_id original_end_commit_id).each do |attr|
          refute_nil thread.send(attr)
        end
      end

      test "valid file level thread has no values for blob attributes" do
        thread = create(:pull_request_review_thread, :on_file, pull_request: @pull)

        assert thread.valid?
        %w(blob_commit_oid blob_path blob_position).each do |attr|
          assert_nil thread.send(attr)
        end
      end

      test "valid file level thread does not have a compressed_diff_hunk" do
        thread = create(:pull_request_review_thread, :on_file, pull_request: @pull)

        assert thread.valid?
        assert_nil thread.compressed_diff_hunk
      end

      test "fails when specified commits don't exist" do
        review = @pull.pending_review_for(user: @pull.repository.owner)
        invalid_oid = "f" * 40
        thread = build(:pull_request_review_thread,
          :on_file,
          pull_request: @pull,
          pull_request_review: review,
          commit_id: invalid_oid,
        )

        refute thread.valid?
        assert_equal ["is not part of the pull request"], thread.errors[:end_commit_oid]
      end

      test "marks file-level comments as outdated when file is removed from the pull request" do
        args = {
          author: @owner,
          review: @pull.pending_review_for(user: @owner),
          body: "comment",
          path: "file2.txt",
          subject_type: :file,
          diff_range: {
            end_commit_oid: @commit.oid
          }
        }

        thread, _ = ReviewThreadCreator.new(**args).create_thread
        assert thread.outdated?
      end

      test "does not mark a file-level comment on a renamed file as outdated" do
        args = {
          author: @owner,
          review: @pull.pending_review_for(user: @owner),
          body: "comment",
          path: "renamed_empty_file",
          subject_type: :file,
          diff_range: {
            end_commit_oid: @commit.oid
          }
        }

        thread, _ = ReviewThreadCreator.new(**args).create_thread
        refute thread.outdated?
      end

      test "does not mark a file-level comment on a renamed file as outdated when commenting on latest" do
        args = {
          author: @owner,
          review: @pull.pending_review_for(user: @owner),
          body: "comment",
          path: "renamed_empty_file",
          subject_type: :file,
        }

        thread, _ = ReviewThreadCreator.new(**args).create_thread
        refute thread.outdated?
      end

      test "does not mark a file-level comment on a deleted file as outdated" do
        args = {
          author: @owner,
          review: @pull.pending_review_for(user: @owner),
          body: "comment",
          path: "readme.txt",
          subject_type: :file,
          diff_range: {
            end_commit_oid: @commit.oid
          }
        }

        thread, _ = ReviewThreadCreator.new(**args).create_thread
        refute thread.outdated?
      end

      test "does not mark file-level comments as outdated when the file is present in the pull request diff" do
        args = {
          author: @owner,
          review: @pull.pending_review_for(user: @owner),
          body: "comment",
          path: "file1.txt",
          subject_type: :file,
          diff_range: {
            end_commit_oid: @commit.oid
          }
        }

        thread, _ = ReviewThreadCreator.new(**args).create_thread
        refute thread.outdated?
      end

      test "marks file-level comments as no longer outdated if a file is renamed back to its original name in the latest commit" do
        args = {
          author: @owner,
          review: @pull.pending_review_for(user: @owner),
          body: "comment",
          path: "original_file_name.txt",
          subject_type: :file,
          diff_range: {
            end_commit_oid: @commit.oid
          }
        }

        thread, _ = ReviewThreadCreator.new(**args).create_thread
        refute thread.outdated?
      end

      test "marks file-level comments as outdated when the file that is added in the branch but later renamed" do
        args = {
          author: @owner,
          review: @pull.pending_review_for(user: @owner),
          body: "comment",
          path: "rename_me.txt",
          subject_type: :file,
          diff_range: {
            end_commit_oid: @commit.oid
          }
        }
        # note to self: this is failing because the pr's diff actually doesn't include "rename_me.txt" anywhere
        # because the file itself was created in the PR then renamed so there is nothing about it.

        thread, _ = ReviewThreadCreator.new(**args).create_thread
        assert thread.outdated?
      end

      test "does not mark file-level comments as outdated when commenting on the latest version of the pull request" do
        args = {
          author: @owner,
          review: @pull.pending_review_for(user: @owner),
          body: "comment",
          path: "file1.txt",
          subject_type: :file
        }

        thread, _ = ReviewThreadCreator.new(**args).create_thread
        refute thread.outdated?
      end

      test "throws an error when commeting on a file not currently in the diff" do
        args = {
          author: @owner,
          review: @pull.pending_review_for(user: @owner),
          body: "comment",
          path: "file2.txt",
          subject_type: :file
        }

        thread, _ = ReviewThreadCreator.new(**args).create_thread
        assert thread.errors[:path].present?
      end
    end

    test "fails validation with no position" do
      review = @pull.pending_review_for(user: @repo.owner)
      thread = review.build_thread(
        pull_request: @pull,
        path: "file1.txt",
        position: nil,
        commit_id: @pull.head_sha,
      )

      refute thread.valid?
      assert_equal ["is invalid"], thread.errors[:position]
    end

    test "fails validation with 0 position" do
      review = @pull.pending_review_for(user: @repo.owner)
      thread = review.build_thread(
        pull_request: @pull,
        path: "file1.txt",
        position: 0,
        commit_id: @pull.head_sha,
      )

      refute thread.valid?
      assert_equal ["is invalid"], thread.errors[:position]
    end

    test "fails validation with negative position" do
      review = @pull.pending_review_for(user: @repo.owner)
      thread = review.build_thread(
        pull_request: @pull,
        path: "file1.txt",
        position: -2,
        commit_id: @pull.head_sha,
      )

      refute thread.valid?
      assert_equal ["is invalid"], thread.errors[:position]
    end

    test "fails validation with no path" do
      review = @pull.pending_review_for(user: @repo.owner)
      thread = review.build_thread(
        pull_request: @pull,
        path: "nonexistent_file.txt",
        position: 1,
        commit_id: @pull.head_sha,
      )

      refute thread.valid?
      assert_equal ["is invalid"], thread.errors[:path]
    end

    test "fails validation on commits outside the pull request" do
      ref = @pull.head_repository.heads.find("cr-line-endings")
      head_oid = ref.target_oid
      base_oid = ref.target.parent_oids.first

      comparison = @pull.pull_comparison(start_oid: base_oid, end_oid: head_oid, base_oid: base_oid)

      review = @pull.pending_review_for(user: @pull.repository.owner, head_sha: head_oid)
      thread = review.build_thread(
        path: "file1.txt",
        position: 1,
      )
      thread.build_first_comment(
        body: "don'tcare",
        path: "file1.txt",
        diff: comparison.diffs,
      ) # Hack! Only need this to set diff on the thread.

      refute thread.valid?
      assert_equal ["is not part of the pull request"], thread.errors[:end_commit_oid]
    end

    test "fails validation on start commit outside the pull request" do
      base_commit = @pull.repository.commits.find(@pull.merge_base)
      before_pr = base_commit.parent_oids.first
      comparison = @pull.pull_comparison(start_oid: before_pr)

      review = @pull.pending_review_for(user: @pull.repository.owner)
      thread = review.build_thread(
        path: "file1.txt",
        position: 1,
      )
      thread.build_first_comment(
        body: "don'tcare",
        path: "file1.txt",
        diff: comparison.diffs,
      ) # Hack! Only need this to set diff on the thread.

      refute thread.valid?
      assert_equal ["is not part of the pull request"], thread.errors[:start_commit_oid]
    end

    context "end_position_data validation" do
      test "fails when specified commits don't exist" do
        review = @pull.pending_review_for(user: @pull.repository.owner)
        invalid_oid = "f" * 40
        diff = GitHub::Diff.new(@pull.repository, invalid_oid, invalid_oid, base_sha: invalid_oid)
        thread = review.build_thread
        thread.build_first_comment(
          body: "good code!",
          path: "aquaman.txt",
          diff: diff,
          line: 5,
        )

        refute thread.valid?
        expected = ["is not part of the pull request"]
        assert_equal expected, thread.errors[:start_commit_oid]
        assert_equal expected, thread.errors[:end_commit_oid]
        assert_equal ["could not be found"], thread.errors[:base_commit_oid]
      end

      test "fails for start or end outside PR's range" do
        review = @pull.pending_review_for(user: @pull.repository.owner)

        # "magic" oids from further up the base branch on the base repo
        diff = GitHub::Diff.new(@pull.repository, "c982c677264e49febbbc6607778c63210e893270",
          "7a63e9bd749c88b2763faa07478830fda1800f3b", base_sha: "c982c677264e49febbbc6607778c63210e893270")
        thread = review.build_thread
        thread.build_first_comment(
          body: "good code!",
          path: "aquaman.txt",
          diff: diff,
          line: 5,
        )

        refute thread.valid?
        expected = ["is not part of the pull request"]
        assert_equal expected, thread.errors[:start_commit_oid]
        assert_equal expected, thread.errors[:end_commit_oid]
      end

      test "fails for an invalid path" do
        review = @pull.pending_review_for(user: @pull.repository.owner)
        thread = review.build_thread
        thread.build_first_comment(
          body: "good code!",
          path: "batman.txt",
          line: 5,
        )

        refute thread.valid?
        assert_equal ["is invalid"], thread.errors[:path]
      end

      test "fails for a string line" do
        review = @pull.pending_review_for(user: @pull.repository.owner)
        thread = review.build_thread
        thread.build_first_comment(
          body: "good code!",
          path: "file1.txt",
          line: "foo",
        )

        refute thread.valid?
        assert_equal ["required and an integer greater than zero"], thread.errors[:line]
      end

      test "fails for a line of 0" do
        review = @pull.pending_review_for(user: @pull.repository.owner)
        thread = review.build_thread
        thread.build_first_comment(
          body: "good code!",
          path: "file1.txt",
          line: 0,
        )

        refute thread.valid?
        assert_equal ["required and an integer greater than zero"], thread.errors[:line]
      end

      test "fails for a line below 0" do
        review = @pull.pending_review_for(user: @pull.repository.owner)
        thread = review.build_thread
        thread.build_first_comment(
          body: "good code!",
          path: "file1.txt",
          line: -5,
        )

        refute thread.valid?
        assert_equal ["required and an integer greater than zero"], thread.errors[:line]
      end

      test "fails for a valid line outside the diff context" do
        review = @pull.pending_review_for(user: @pull.repository.owner)
        thread = review.build_thread
        thread.build_first_comment(
          body: "good code!",
          path: "file1.txt",
          line: 13,
        )

        refute thread.valid?
        assert_equal ["must be part of the diff"], thread.errors[:line]
      end
    end

    context "during an import" do
      test "does not fail validation on commits outside the pull request" do
        pull_request = ImportablePullRequest.find(@pull.id)
        user = T.must(pull_request.repository).owner

        ref = T.must(pull_request.head_repository).heads.find("cr-line-endings")
        head_oid = ref.target_oid
        base_oid = ref.target.parent_oids.first

        diff_hunk = <<~EOF
          @@ -1 +1,4 @@
           # force-push-test
          +
          +Add a line
          +Add a second line
        EOF

        review = pull_request.pending_review_for(user: T.must(user), head_sha: head_oid)

        thread = review.review_threads.build(
          pull_request: pull_request,
          pull_request_review: review,

          outdated: true,
          diff_hunk: diff_hunk,
          path: "file1.txt",
          commit_id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          original_position: 1,
          original_start_commit_id: base_oid,
          original_base_commit_id: pull_request.merge_base
        )

        comment = thread.review_comments.build(
          pull_request: pull_request,
          pull_request_review_thread: thread,
          user: user,
          body: "Comment body"
        )

        assert comment.save
      end

      test "fails validation on commits outside the pull request when thread is not outdated" do
        pull_request = ImportablePullRequest.find(@pull.id)
        user = T.must(pull_request.repository).owner

        ref = T.must(pull_request.head_repository).heads.find("cr-line-endings")
        head_oid = ref.target_oid
        base_oid = ref.target.parent_oids.first

        diff_hunk = <<~EOF
          @@ -1 +1,4 @@
           # force-push-test
          +
          +Add a line
          +Add a second line
        EOF

        review = pull_request.pending_review_for(user: T.must(user), head_sha: head_oid)

        thread = review.review_threads.build(
          pull_request: pull_request,
          pull_request_review: review,

          diff_hunk: diff_hunk,
          path: "file1.txt",
          commit_id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          original_position: 1,
          original_start_commit_id: base_oid,
          original_base_commit_id: pull_request.merge_base
        )

        comment = thread.review_comments.build(
          pull_request: pull_request,
          pull_request_review_thread: thread,
          user: user,
          body: "Comment body"
        )

        refute thread.valid?
        assert_equal thread.errors[:end_commit_oid], ["is not part of the pull request"]
      end

      test "fails validation on commits outside the pull request when original_position is not present" do
        pull_request = ImportablePullRequest.find(@pull.id)
        user = T.must(pull_request.repository).owner

        ref = T.must(pull_request.head_repository).heads.find("cr-line-endings")
        head_oid = ref.target_oid
        base_oid = ref.target.parent_oids.first

        diff_hunk = <<~EOF
          @@ -1 +1,4 @@
           # force-push-test
          +
          +Add a line
          +Add a second line
        EOF

        review = pull_request.pending_review_for(user: T.must(user), head_sha: head_oid)

        thread = review.review_threads.build(
          pull_request: pull_request,
          pull_request_review: review,

          outdated: true,
          diff_hunk: diff_hunk,
          path: "file1.txt",
          commit_id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          original_start_commit_id: base_oid,
          original_base_commit_id: pull_request.merge_base
        )

        comment = thread.review_comments.build(
          pull_request: pull_request,
          pull_request_review_thread: thread,
          user: user,
          body: "Comment body"
        )

        refute thread.valid?
        assert_equal thread.errors[:end_commit_oid], ["is not part of the pull request"]
      end

      test "fails validation on commits outside the pull request when diff_hunk is not present" do
        pull_request = ImportablePullRequest.find(@pull.id)
        user = T.must(pull_request.repository).owner

        ref = T.must(pull_request.head_repository).heads.find("cr-line-endings")
        head_oid = ref.target_oid
        base_oid = ref.target.parent_oids.first

        review = pull_request.pending_review_for(user: T.must(user), head_sha: head_oid)

        thread = review.review_threads.build(
          pull_request: pull_request,
          pull_request_review: review,

          outdated: true,
          path: "file1.txt",
          commit_id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          original_position: 1,
          original_start_commit_id: base_oid,
          original_base_commit_id: pull_request.merge_base
        )

        comment = thread.review_comments.build(
          pull_request: pull_request,
          pull_request_review_thread: thread,
          user: user,
          body: "Comment body"
        )

        refute thread.valid?
        assert_equal thread.errors[:end_commit_oid], ["is not part of the pull request"]
      end
    end
  end

  context "#async_current_diff" do
    test "returns the creation_diff with the proper line limits if creation_diff is set" do
      review = @pull.pending_review_for(user: @repo.owner, head_sha: @pull.head_sha)
      diff = GitHub::Diff.new(@pull.repository, "c982c677264e49febbbc6607778c63210e893270", "7a63e9bd749c88b2763faa07478830fda1800f3b", base_sha: "c982c677264e49febbbc6607778c63210e893270")
      thread = review.build_thread
      thread.creation_diff = diff

      assert diff.max_diff_lines, GitHub::Diff::DEFAULT_MAX_DIFF_LINES
      assert thread.send(:async_current_diff).sync.max_diff_lines, GitHub::Diff::DEFAULT_MAX_TOTAL_LINES
    end
  end

  context "#async_diff_relative_position_for_viewer" do
    context "when the comment outside the diff feature flag is enabled" do
      test "returns nil when a passed viewer does not have access to the thread" do
        enable_feature_flag(:comment_outside_the_diff)

        @legacy_thread.review_comments.map { |comment| comment.update_column(:state, "pending") }

        result = @legacy_thread.async_diff_relative_position_for_viewer(viewer: @viewer).sync
        assert_nil result
      end

      test "returns a position when a passed viewer that has access to the thread" do
        enable_feature_flag(:comment_outside_the_diff)

        result = @legacy_thread.async_diff_relative_position_for_viewer(viewer: @owner).sync
        assert_equal 1, result
      end
    end
  end

  context "conversation?" do
    test "is considered a conversation for a thread that is not part of a code scanning review" do
      review = @pull.pending_review_for(user: @owner, head_sha: @pull.head_sha)

      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "file1.txt",
        line: 1,
      ).save!
      review.comment!

      assert_equal true, thread.conversation?

      thread.build_reply(
        user: @owner,
        body: "ok",
      ).save!

      assert_equal true, thread.conversation?
    end

    test "for threads associated with code scanning, they're only considered a conversation once there's a reply" do
      review = @pull.build_code_scanning_variant_review do |r|
        r.user = @owner
      end

      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "file1.txt",
        line: 1,
      ).save!
      review.comment!

      assert_equal false, thread.conversation?

      thread.build_reply(
        user: @owner,
        body: "ok",
      ).save!

      assert_equal true, thread.conversation?
    end

    test "code scanning thread can be resolved by owner if they have enough replies" do
      user = create(:user)

      @pull.reviews.destroy_all

      review = @pull.build_code_scanning_variant_review do |r|
        r.user = user
      end
      review.save!

      thread = review.build_thread
      thread.build_first_comment(
        body: "comment",
        path: "file1.txt",
        line: 1,
      ).save!
      review.comment!

      refute review.pending?
      refute_predicate thread, :conversation?
      refute thread.async_can_resolve(@owner).sync

      thread.build_reply(
        user: user,
        body: "ok",
      ).save!
      thread.reload

      assert_predicate thread, :conversation?
      assert thread.async_can_resolve(@owner).sync
    end
  end

  test "callbacks are accounted for in DeletePullRequestReviewCommentOrchestration, CreateReplyPullRequestReviewCommentOrchestration, and CreateNewPullRequestReviewCommentOrchestration" do
    base_message =
"If this change applies to a callback invoked when creating or deleting a
comment, please ensure that it is applied to the orchestrations responsible
for deleting a comment, creating a new comment, or creating a reply"

    expected_callbacks_and_counts = {
      validate: 8,
      validation: 7,
      initialize: 0,
      find: 0,
      touch: 0,
      save: 5,
      create: 4,
      update: 1,
      destroy: 0,
      commit: 3,
      rollback: 0,
      before_commit: 0,
    }

    unless PullRequestReviewThread.__callbacks.keys == expected_callbacks_and_counts.keys
      fail "New callback type introduced on the PullRequestReviewThread model. \n#{base_message}"
    end

    expected_callbacks_and_counts.each do |name, count|
      assert_equal PullRequestReviewThread.send("_#{name}_callbacks".to_sym).count, count, callback_count_message(name, count, PullRequestReviewThread.send("_#{name}_callbacks".to_sym).count, base_message)
    end
  end

  context "#async_can_resolve" do
    if GitHub.spamminess_check_enabled?
      test "resolves false if the viewer is spammy" do
        content = <<-CONTENTS
    Wonderful
    New
    File
    Here
    CONTENTS

        commit = @repo.commits.create({ message: "add new file", committer: @repo.owner }, @pull.head_sha) do |files|
          files.add("multiline.txt", content)
        end
        with_enqueued_pr_sync_jobs { @repo.heads.find(@pull.head_ref).update(commit, @repo.owner) }
        @pull.reload

        review = @pull.pending_review_for(user: @repo.owner)
        thread = review.build_thread
        comment = thread.build_first_comment(
          body: "multiline comment",
          path: "multiline.txt",
          start_line: 2,
          line: 4,
        )
        thread.save!
        review.comment!

        user = @repo.owner

        Platform::Security::RepositoryAccess.ensure_viewer(user)

        refute_predicate user, :spammy?
        assert thread.async_can_resolve(user).sync, "Expected non-spammy user to be able to resolve the thread"

        user.update! spammy: true
        assert_predicate user, :spammy?
        refute thread.async_can_resolve(user).sync, "Expected spammy user to NOT be able to resolve the thread"
      end
    end

    test "resolves false when PR author is deleted and viewer is nil (anonymous)" do
      content = <<-CONTENTS
  Wonderful
  New
  File
  Here
  CONTENTS

      commit = @repo.commits.create({ message: "add new file", committer: @repo.owner }, @pull.head_sha) do |files|
        files.add("multiline.txt", content)
      end
      with_enqueued_pr_sync_jobs { @repo.heads.find(@pull.head_ref).update(commit, @repo.owner) }
      @pull.reload

      review = @pull.pending_review_for(user: @repo.owner)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "multiline comment",
        path: "multiline.txt",
        start_line: 2,
        line: 4,
      )
      thread.save!
      review.comment!

      @repo.owner.destroy
      thread.reload
      refute thread.async_can_resolve(nil).sync, "Expected nil user not to be able to resolve the thread"
    end
  end

  test "returns original position attributes after reposition" do
    content = <<-CONTENTS
Wonderful
New
File
Here
CONTENTS

    commit = @repo.commits.create({ message: "add new file", committer: @repo.owner }, @pull.head_sha) do |files|
      files.add("multiline.txt", content)
    end
    with_enqueued_pr_sync_jobs { @repo.heads.find(@pull.head_ref).update(commit, @repo.owner) }
    @pull.reload

    review = @pull.pending_review_for(user: @repo.owner)
    thread = review.build_thread
    comment = thread.build_first_comment(
      body: "multiline comment",
      path: "multiline.txt",
      start_line: 2,
      line: 4,
    )
    thread.save

    assert_equal 2, thread.async_start_line.sync.current
    assert_equal 4, thread.async_end_line.sync.current
    assert_equal 4, thread.async_line.sync
    assert_equal 2, thread.async_original_start_line.sync
    assert_equal 4, thread.async_original_line.sync

    new_content = <<-CONTENTS
Welcome
To
My
Wonderful
New
File
Here
CONTENTS

    updated_commit = @repo.commits.create({ message: "add new file", committer: @repo.owner }, @pull.head_sha) do |files|
      files.add("multiline.txt", new_content)
    end
    with_enqueued_pr_sync_jobs { @repo.heads.find(@pull.head_ref).update(updated_commit, @repo.owner) }
    @pull.reload

    thread.reload

    # 3 lines were added to the top of the file, shifting the current positions
    assert_equal 5, thread.async_start_line.sync.current
    assert_equal 7, thread.async_end_line.sync.current
    assert_equal 7, thread.async_line.sync
    # We should still be able to identify the original positions though
    assert_equal 2, thread.async_original_start_line.sync
    assert_equal 4, thread.async_original_line.sync
  end

  context "#outside_diff?" do
    test "returns false when inside the diff" do
      content = <<-CONTENTS
- 9g salt
- 1 1/2 teaspoons sugar
- 298g Unbleached All-Purpose Flour
- 454g ripe (fed) sourdough starter
- 113g lukewarm water
CONTENTS

      commit = @repo.commits.create({ message: "add new file", committer: @repo.owner }, @pull.head_sha) do |files|
        files.add("bread.md", content)
      end
      with_enqueued_pr_sync_jobs { @repo.heads.find(@pull.head_ref).update(commit, @repo.owner) }
      @pull.reload

      review = @pull.pending_review_for(user: @repo.owner)
      thread = review.build_thread
      thread.build_first_comment(
        body: "wow really tho",
        path: "bread.md",
        line: 2,
      )
      thread.save

      assert !thread.outside_diff?
    end

    test "returns true when a comment is left outside the diff" do
      enable_feature_flag(:comment_outside_the_diff)
      content = <<-CONTENTS
a
b
c
d
e
f
g
h
CONTENTS

      @repo.heads.find("master").append_commit({ message: "Update a with more alphabet", committer: @repo.owner }, @repo.owner) do |files|
        files.add("a", content)
      end

      content = <<-CONTENTS
a
b
c
d
e
f
g
h
FFFFFFFFFFFFFFFFFFFFFFFF
CONTENTS

      ref = @repo.heads.create("outside_diff", @repo.heads.find("master").target, @repo.owner)
      ref.append_commit({ message: "FFFFFFF", committer: @repo.owner }, @repo.owner) do |files|
        files.add("a", content)
      end

      issue = create(:issue, repository: @repo)
      pull = PullRequest.create_for(
        @repo,
        base: "master",
        head: ref.name,
        user: @owner,
        issue: issue,
      )

      args = {
        author: @owner,
        review: pull.pending_review_for(user: @owner),
        body: "this can be removed now tbqh",
        path: "a",
        line: 1
      }
      thread, _ = ReviewThreadCreator.new(**args).create_thread

      assert thread.pull_request_review.comment!

      assert thread.outside_diff?
    end
  end

  context "resolve" do
    test "does not live update pull request if the base does not require review thread resolution" do
      protected_branch = create(:protected_branch,
        repository: @repo,
        creator: @owner
      )
      protected_branch.clear_required_review_thread_resolution
      protected_branch.save!

      content = <<-CONTENTS
      Wonderful
      New
      File
      Here
      CONTENTS

      commit = @repo.commits.create({ message: "add new file", committer: @repo.owner }, @pull.head_sha) do |files|
        files.add("multiline.txt", content)
      end
      with_enqueued_pr_sync_jobs { @repo.heads.find(@pull.head_ref).update(commit, @repo.owner) }
      @pull.reload
      review = @pull.pending_review_for(user: @repo.owner)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "multiline comment",
        path: "multiline.txt",
        start_line: 2,
        line: 4,
      )
      thread.save!
      review.comment!

      GitHub::WebSocket.expects(:notify_pull_request_channel).never
      thread.resolve(resolver: @owner)
    end

    test "live updates pull request if the base requires review thread resolution" do
      protected_branch = create(:protected_branch,
        repository: @repo,
        creator: @owner
      )
      protected_branch.enable_required_review_thread_resolution
      protected_branch.save!

      content = <<-CONTENTS
      Wonderful
      New
      File
      Here
      CONTENTS

      commit = @repo.commits.create({ message: "add new file", committer: @repo.owner }, @pull.head_sha) do |files|
        files.add("multiline.txt", content)
      end
      with_enqueued_pr_sync_jobs { @repo.heads.find(@pull.head_ref).update(commit, @repo.owner) }
      @pull.reload
      review = @pull.pending_review_for(user: @repo.owner)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "multiline comment",
        path: "multiline.txt",
        start_line: 2,
        line: 4,
      )
      thread.save!
      review.comment!

      GitHub::WebSocket.expects(:notify_pull_request_channel)
      thread.resolve(resolver: @owner)
    end

    test "enqueues auto-merge job if the base requires review thread resolution" do
      protected_branch = create(:protected_branch,
        repository: @repo,
        creator: @owner
      )
      protected_branch.enable_required_review_thread_resolution
      protected_branch.save!

      content = <<-CONTENTS
      Wonderful
      New
      File
      Here
      CONTENTS

      commit = @repo.commits.create({ message: "add new file", committer: @repo.owner }, @pull.head_sha) do |files|
        files.add("multiline.txt", content)
      end
      with_enqueued_pr_sync_jobs { @repo.heads.find(@pull.head_ref).update(commit, @repo.owner) }
      @pull.reload
      review = @pull.pending_review_for(user: @repo.owner)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "multiline comment",
        path: "multiline.txt",
        start_line: 2,
        line: 4,
      )
      thread.save!
      review.comment!
      thread.pull_request.expects(:enqueue_auto_merge_job_if_enabled).once
      thread.resolve(resolver: @owner)
    end
  end

  context "unresolve" do
    test "live updates pull request if the base requires review thread resolution" do
      protected_branch = create(:protected_branch,
        repository: @repo,
        creator: @owner
      )
      protected_branch.enable_required_review_thread_resolution
      protected_branch.save!

      content = <<-CONTENTS
      Wonderful
      New
      File
      Here
      CONTENTS

      commit = @repo.commits.create({ message: "add new file", committer: @repo.owner }, @pull.head_sha) do |files|
        files.add("multiline.txt", content)
      end
      with_enqueued_pr_sync_jobs { @repo.heads.find(@pull.head_ref).update(commit, @repo.owner) }
      @pull.reload
      review = @pull.pending_review_for(user: @repo.owner)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "multiline comment",
        path: "multiline.txt",
        start_line: 2,
        line: 4,
      )
      thread.save!
      review.comment!

      thread.resolve(resolver: @owner)
      GitHub::WebSocket.expects(:notify_pull_request_channel)
      thread.unresolve(unresolver: @owner)
    end

    test "does not live update pull request if the base does not require review thread resolution" do
      protected_branch = create(:protected_branch,
        repository: @repo,
        creator: @owner
      )
      protected_branch.clear_required_review_thread_resolution
      protected_branch.save!

      content = <<-CONTENTS
      Wonderful
      New
      File
      Here
      CONTENTS

      commit = @repo.commits.create({ message: "add new file", committer: @repo.owner }, @pull.head_sha) do |files|
        files.add("multiline.txt", content)
      end
      with_enqueued_pr_sync_jobs { @repo.heads.find(@pull.head_ref).update(commit, @repo.owner) }
      @pull.reload
      review = @pull.pending_review_for(user: @repo.owner)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "multiline comment",
        path: "multiline.txt",
        start_line: 2,
        line: 4,
      )
      thread.save!
      review.comment!

      thread.resolve(resolver: @owner)
      GitHub::WebSocket.expects(:notify_pull_request_channel).never
      thread.unresolve(unresolver: @owner)
    end
  end

  test "publishes an event to Hydro when resolving and unresolving a thread" do
    content = <<-CONTENTS
    Wonderful
    New
    File
    Here
    CONTENTS

    commit = @repo.commits.create({ message: "add new file", committer: @repo.owner }, @pull.head_sha) do |files|
      files.add("multiline.txt", content)
    end
    with_enqueued_pr_sync_jobs { @repo.heads.find(@pull.head_ref).update(commit, @repo.owner) }
    @pull.reload
    review = @pull.pending_review_for(user: @repo.owner)
    thread = review.build_thread
    comment = thread.build_first_comment(
      body: "multiline comment",
      path: "multiline.txt",
      start_line: 2,
      line: 4,
    )
    thread.save!
    review.comment!
    thread.resolve(resolver: @owner)

    assert_hydro_published_partial(
      {
        pull_request_review_thread: Hydro::EntitySerializer.pull_request_review_thread(thread),
        repository: Hydro::EntitySerializer.repository(Repositories.domain.by_id(@repo.id)),
        actor: Hydro::EntitySerializer.user(@owner),
      },
      schema: "github.pull_requests.v1.PullRequestReviewThreadResolveOrUnresolve",
      topic: "github.pull_requests.v1.PullRequestReviewThreadResolve"
    )

    thread.unresolve(unresolver: @owner)

    assert_hydro_published(
      {
        pull_request_review_thread: Hydro::EntitySerializer.pull_request_review_thread(thread),
        repository: Hydro::EntitySerializer.repository(Repositories.domain.by_id(@repo.id)),
        actor: Hydro::EntitySerializer.user(@owner),
      },
      schema: "github.pull_requests.v1.PullRequestReviewThreadResolveOrUnresolve",
      topic: "github.pull_requests.v1.PullRequestReviewThreadUnresolve"
    )
  end

  context "validations" do
    # File level threads is a special case where we skip
    # `before_validations` calls for setting position related attributes.
    # and as a result we skip validations for file level threads.
    # In order not to repeat the same test specs for diff line threads (the default)
    # we can consider test specs outside of the `file level threads` context
    # are working for all types of threads including `file_level threads`
    # unless we have contrary test specs within the `file level thread` context
    # then we consider these test specs as applicable on other types of threads.

    context "file level thread" do
      # not going to test every edge case as above, but just making sure that the
      # mechanism works on PR sync too
      test "threads get marked as outdated on pull request update" do
        args = {
          author: @owner,
          review: @pull.pending_review_for(user: @owner),
          body: "comment",
          path: "file1.txt",
          subject_type: :file
        }

        thread, _ = ReviewThreadCreator.new(**args).create_thread
        refute_predicate thread, :outdated?

        with_enqueued_pr_sync_jobs do
          @ref.append_commit({ message: "remove file1", committer: @repo.owner }, @repo.owner) do |files|
            files.remove("file1.txt")
          end
        end

        thread.reload
        assert_predicate thread, :outdated?
      end
    end
  end

  test "fails validation on a binary file" do
    metadata = { message: "blah", committer: @pull.repository.owner }
    commit = with_enqueued_pr_sync_jobs do
      @pull.repository.heads.find("topic").append_commit(metadata, @pull.repository.owner) do |files|
        files.add("binary_file", "\xff\x00\x2a")
      end
    end

    assert commit.diff["binary_file"].binary?
    assert_equal commit.oid, @pull.reload.head_sha

    review = @pull.pending_review_for(user: @pull.repository.owner)
    thread = review.build_thread
    thread.build_first_comment(
      path: "binary_file",
      line: 1,
      body: "text",
    )

    refute thread.valid?
    assert_equal ["can't be a binary file"], thread.errors[:path]
  end

  test "succeeds validation on a binary file for a file-level thread" do
    metadata = { message: "blah", committer: @pull.repository.owner }
    commit = with_enqueued_pr_sync_jobs do
      @pull.repository.heads.find("topic").append_commit(metadata, @pull.repository.owner) do |files|
        files.add("binary_file", "\xff\x00\x2a")
      end
    end

    assert commit.diff["binary_file"].binary?
    assert_equal commit.oid, @pull.reload.head_sha

    review = @pull.pending_review_for(user: @pull.repository.owner)
    thread = review.build_thread(subject_type: :file)
    thread.build_first_comment(
      path: "binary_file",
      line: 1,
      body: "text",
    )

    assert thread.valid?
  end
end

class PullRequestReviewThreadCreationtest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :empty)

    root_commit = @repo.commits.create({ message: "adding a file", committer: @repo.owner }) do |files|
      files.add("README.md", [
        "- Line 1",
        "- Line 2",
        "- Line 3",
        "",
      ].join("\n"))
    end
    @repo.heads.create("main", root_commit.oid, @repo.owner)

    topic = @repo.heads.create("topic", root_commit.oid, @repo.owner)
    topic_commit = topic.append_commit({ message: "update README", committer: @repo.owner }, @repo.owner) do |files|
      files.add("README.md", [
        "- Line 1",
        "- Line 2",
        "- Line 3",
        "- Line 4",
        "- Line 5",
        "- Line 6",
        "",
      ].join("\n"))
    end

    @pull_request = create(
      :pull_request,
      repository: @repo,
      user: @repo.owner,
      base_ref: "main",
      base_sha: root_commit.oid,
      head_ref: "topic",
      head_sha: topic_commit.oid,
    )

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  context ".create!" do
    test "repositions threads if the PR head has changed" do
      # This test simulates the situation where a review thread is created
      # near-simultaneously with a push to the PR's head branch.
      # The thread needs to be re-positioned immediately to retain the
      # reviewer's intended position.

      review_thread = build(
        :pull_request_review_thread, :on_line,
        pull_request_id: @pull_request.id,
        commit_id: @pull_request.head_sha,
        original_position: 4,
        path: "README.md",
      )

      topic = @repo.heads.find("topic")
      new_commit = topic.append_commit({ message: "Prepend a line", committer: @repo.owner }, @repo.owner) do |files|
        files.add("README.md", [
          "# A new header",
          "",
          "- Line 1",
          "- Line 2",
          "- Line 3",
          "- Line 4",
          "- Line 5",
          "- Line 6",
          "",
        ].join("\n"))
      end
      @pull_request.update!(head_sha: new_commit.oid)

      assert_nothing_raised { review_thread.save! }
      assert_equal 6, review_thread.position
    end
  end
end

class PullRequestReviewAsyncDiffLinesTest < GitHub::TestCase
  fixtures do
    @ari    = create(:user, login: "ari")
    @source = create(:repository, owner: @ari, from_example: :review_comment_source)
    @bwalsh = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @bwalsh, fork_repo: @source, from_example: :review_comment_fork)
    @source.add_member @bwalsh

    @issue = create(:issue, user: @bwalsh, repository: @source)
    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @issue,
        user: @bwalsh,
      )
    @issue.pull_request = @pull

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  context "#async_diff_lines" do
    test "provides an array of diff lines" do
      comment =
        create(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: "I really like the new SUPERBOY casing. Good job.",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
        )

      lines = comment.pull_request_review_thread.async_diff_lines(max_context_lines: 15).sync
      assert_equal [
        { type: :hunk,     position: 0, left: 14, right: 14, no_newline_at_end: false, cache_code: :miss,
          text: "@@ -15,24 +15,26 @@ Comic Books — the first version of Aquaman, was created by writer Mort Weising",
          html: "@@ -15,24 +15,26 @@ Comic Books — the first version of Aquaman, was created by writer Mort Weising" },
        { type: :context,  position: 1, left: 15, right: 15, no_newline_at_end: false, cache_code: :miss,
          text: " and artist Paul Norris, appeared in a backup feature in DC Comics' More Fun",
          html: "and artist Paul Norris, appeared in a backup feature in DC Comics&#39; More Fun" },
        { type: :context,  position: 2, left: 16, right: 16, no_newline_at_end: false, cache_code: :miss,
          text: " Comics #73-107 (Nov. 1941 - Feb. 1946), after which the series dropped superhero",
          html: "Comics #73-107 (Nov. 1941 - Feb. 1946), after which the series dropped superhero" },
        { type: :context,  position: 3, left: 17, right: 17, no_newline_at_end: false, cache_code: :miss,
          text: " stories to become a humor title. Aquaman's feature moved to Adventure Comics",
          html: "stories to become a humor title. Aquaman&#39;s feature moved to Adventure Comics" },
        { type: :deletion, position: 4, left: 18, right: 17, no_newline_at_end: false, cache_code: :miss,
          text: "-#103-284 (April 1946 - May 1961) as a backup to the comic book's star, Superboy.",
          html: "#103-284 (April 1946 - May 1961) as a backup to the comic book&#39;s star, <span class=\"x x-first x-last\">Superboy</span>." },
        { type: :addition, position: 5, left: 18, right: 18, no_newline_at_end: false, cache_code: :miss,
          text: "+#103-284 (April 1946 - May 1961) as a backup to the comic book's star, SUPERBOY.",
          html: "#103-284 (April 1946 - May 1961) as a backup to the comic book&#39;s star, <span class=\"x x-first x-last\">SUPERBOY</span>." },
      ], lines
    end

    test "supports truncated diffs" do
      comment =
        create(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: "Adventure Comics has confirmed the relevant details.",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 48
        )

      lines = comment.pull_request_review_thread.async_diff_lines(max_context_lines: 15).sync

      assert_equal [
        { type: :context,  position: 19, left: 29, right: 29, no_newline_at_end: false, cache_code: :miss,
          text: " ",
          html: "<br>" },
        { type: :context,  position: 20, left: 30, right: 30, no_newline_at_end: false, cache_code: :miss,
          text: " Writer Robert Bernstein and penciler-inker Ramona Fradon, one of the few female",
          html: "Writer Robert Bernstein and penciler-inker Ramona Fradon, one of the few female" },
        { type: :context,  position: 21, left: 31, right: 31, no_newline_at_end: false, cache_code: :miss,
          text: " comic artists of that period, introduced the Silver Age version of Aquaman in",
          html: "comic artists of that period, introduced the Silver Age version of Aquaman in" },
        { type: :context,  position: 22, left: 32, right: 32, no_newline_at_end: false, cache_code: :miss,
          text: " Adventure Comics #260 (May 1959), providing a new, substantially different",
          html: "Adventure Comics #260 (May 1959), providing a new, substantially different" },
        { type: :context,  position: 23, left: 33, right: 33, no_newline_at_end: false, cache_code: :miss,
          text: " origin for the character.[2] Bernstein scripted through at least #282 (March",
          html: "origin for the character.[2] Bernstein scripted through at least #282 (March" },
        { type: :context,  position: 24, left: 34, right: 34, no_newline_at_end: false, cache_code: :miss,
          text: " 1961), introducing such major characters as Aqualad and Aquagirl, while Fradon's",
          html: "1961), introducing such major characters as Aqualad and Aquagirl, while Fradon&#39;s" },
        { type: :context,  position: 25, left: 35, right: 35, no_newline_at_end: false, cache_code: :miss,
          text: " art established the look of Aquaman for several years. Aquaman continued to",
          html: "art established the look of Aquaman for several years. Aquaman continued to" },
        { type: :deletion, position: 26, left: 36, right: 35, no_newline_at_end: false, cache_code: :miss,
          text: "-appear in Adventure Comics until issue #284 (May 1961), when the feature moved",
          html: "appear in Adventure Comics until issue #284 (May 1961), when the feature moved" },
        { type: :addition, position: 27, left: 36, right: 36, no_newline_at_end: false, cache_code: :miss,
          text: "+<!-- TODO: check with Adventure Comics to confirm issue# and date -->",
          html: "&lt;!-- TODO: check with Adventure Comics to confirm issue# and date --&gt;" },
      ], lines
    end

    test "with multi-line comment that exceeds maximum excerpt range" do
      review = @pull.reviews.create!(user: @ari, head_sha: @pull.head_sha)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 2,
        start_side: :right,
        line: 6,
        side: :right,
      )
      comment.save!

      assert_equal 5, thread.async_diff_lines(max_context_lines: 15).sync.size

      PullRequestReviewThread.stub_const(:MAX_MULTI_LINE_EXCERPT_LINES, 4) do
        assert_equal 4, thread.async_diff_lines(max_context_lines: 15).sync.size
      end
    end

    test "with multi-line comment includes only selected range" do
      review = @pull.reviews.create!(user: @ari, head_sha: @pull.head_sha)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 2,
        start_side: :right,
        line: 6,
        side: :right,
      )
      comment.save!

      lines = thread.async_diff_lines(max_context_lines: 15).sync.to_a
      assert_equal 5, lines.length, "enumerator length should match the size of the selected range"
      assert_equal 2, lines.first[:right], "first line position should match start line position"
      assert_equal 6, lines.last[:right], "last line position should match line position"
    end

    test "with a single line comment" do
      review = @pull.reviews.create!(user: @ari, head_sha: @pull.head_sha)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman.txt",
        diff: @pull.historical_comparison.diffs,
        line: 6,
        side: :right,
      )
      comment.save!

      max_context_lines = 15
      lines = thread.async_diff_lines(max_context_lines: max_context_lines).sync.to_a
      assert_equal max_context_lines, lines.length
    end
  end

  context "#async_file_level_diff_lines" do
    test "provides an array of diff lines fixed to the top of the diff" do
      comment =
        create(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: "I really like the new SUPERBOY casing. Good job.",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26,
          subject_type: "file"
        )

      lines = comment.pull_request_review_thread.async_file_level_diff_lines(max_context_lines: 3).sync
      assert_equal [
        { type: :context, position: 1,
          text:  " Aquaman is a comic book superhero who appears in DC Comics. Created by Paul",
          html:  "Aquaman is a comic book superhero who appears in DC Comics. Created by Paul",
          left: 1, right: 1, no_newline_at_end: false, cache_code: :miss }
        ], lines
    end

    test "supports truncated diffs" do
      comment =
        create(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: "I really like the new SUPERBOY casing. Good job.",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26,
          subject_type: "file"
        )

      lines = comment.pull_request_review_thread.async_file_level_diff_lines(max_context_lines: 15).sync

      assert_equal [
        { type: :context,
          text: " Aquaman is a comic book superhero who appears in DC Comics. Created by Paul",
          html: "Aquaman is a comic book superhero who appears in DC Comics. Created by Paul",
          position: 1, left: 1, right: 1, no_newline_at_end: false, cache_code: :miss }
        ], lines
    end
  end

  context "#excerpt_truncated?" do
    test "with a single line comment" do
      review = @pull.reviews.create!(user: @ari, head_sha: @pull.head_sha)
      thread = review.build_thread
      thread.build_first_comment(
        body: "comment",
        path: "aquaman.txt",
        diff: @pull.historical_comparison.diffs,
        line: 6,
        side: :right,
      )

      refute_predicate thread, :excerpt_truncated?
    end

    test "with a multi-line comment" do
      review = @pull.reviews.create!(user: @ari, head_sha: @pull.head_sha)
      thread = review.build_thread
      thread.build_first_comment(
        body: "comment",
        path: "aquaman.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 2,
        start_side: :right,
        line: 6,
        side: :right,
      )

      refute_predicate thread, :excerpt_truncated?
    end

    test "with a multi-line comment that exceeds maximum range" do
      review = @pull.reviews.create!(user: @ari, head_sha: @pull.head_sha)
      thread = review.build_thread
      thread.build_first_comment(
        body: "comment",
        path: "aquaman.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 2,
        start_side: :right,
        line: 6,
        side: :right,
      )
      thread.save!

      PullRequestReviewThread.stub_const(:MAX_MULTI_LINE_EXCERPT_LINES, 3) do
        assert_predicate thread, :excerpt_truncated?
      end
    end
  end

  context "#diff_hunk_is_truncated?" do
    test "truncation check for truncated diff hunks" do
      comment =
        create(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: "Adventure Comics has confirmed the relevant details.",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 48
        )

      assert_predicate comment.pull_request_review_thread, :diff_hunk_is_truncated?
    end

    test "truncation check for non-truncated diff hunks" do
      comment =
        create(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: "I really like the new SUPERBOY casing. Good job.",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
        )

      refute_predicate comment.pull_request_review_thread, :diff_hunk_is_truncated?
    end

    test "truncation check for unavailable diff entries" do
      comment =
        create(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: "I really like the new SUPERBOY casing. Good job.",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
        )
      comment.stubs(:diff_entry).returns(nil)

      assert_nil comment.diff_entry
      refute_predicate comment.pull_request_review_thread, :diff_hunk_is_truncated?
    end

    test "truncation check for unavailable diff entry text" do
      comment =
        create(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: "I really like the new SUPERBOY casing. Good job.",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
        )
      diff_entry = comment.diff_entry
      diff_entry.stubs(:text).returns(nil)

      assert_nil comment.diff_entry.text
      refute_predicate comment.pull_request_review_thread, :diff_hunk_is_truncated?
    end
  end

  test "#preload_original_diff" do
    comment =
      create(:pull_request_review_comment, pull_request: @pull,
        user: @bwalsh,
        body: "YeeAaAaa",
        path: "aquaman.txt",
        original_position: 26,
        commit_id: @pull.head_sha,
      )

    comment.pull_request_review_thread.preload_original_diff
    diff = comment.original_pull_request_comparison.diffs

    assert_equal ["aquaman.txt"], diff.paths
    assert_equal GitHub::Diff::DEFAULT_MAX_TOTAL_LINES, diff.max_diff_lines
    assert_equal GitHub::Diff::DEFAULT_MAX_TOTAL_SIZE, diff.max_diff_size
  end
end
