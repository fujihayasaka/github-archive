# typed: true
# frozen_string_literal: true

class Platform::Models::PullRequestSummaryDelta
  delegate :a_sha, :a_path, :b_sha, :b_path, :deleted?, :status, :old_file, :new_file, :additions, :deletions, :is_a?, to: :delta

  attr_reader :delta, :pull, :user, :comparison

  def initialize(delta:, pull:, user:, comparison:)
    @delta = delta
    @pull = pull
    @user = user
    @comparison = comparison
  end

  def unresolved_comment_count
    Platform::Loaders::PullRequest::ReviewThreads.load(pull.id, user, path: path).then do |threads|
      GitHub::PrefillAssociations.prefill_batch_method(threads, :prelude_all_review_comments, user)
      threads.reduce(0) do |sum, thread|
        unresolved_comment_count = !thread.resolved? ? thread.comments.count : 0
        sum + unresolved_comment_count
      end
    end
  end

  def total_comments_count
    Platform::Loaders::PullRequest::ReviewThreads.load(pull.id, user, path: path).then do |threads|
      GitHub::PrefillAssociations.prefill_batch_method(threads, :prelude_all_review_comments, user)
      threads.reduce(0) do |sum, thread|
        sum + thread.comments.count
      end
    end
  end

  def total_annotations_count
    pull.async_repository.then do |repo|
      Platform::Loaders::CheckAnnotationsCount.load(repo, comparison.end_commit.oid, path)
    end
  end

  def viewer_viewed_state
    user_reviewed_files = pull.user_reviewed_files_for(user)
    if user_reviewed_files.reviewed?(path)
      :viewed
    elsif user_reviewed_files.dismissed?(path)
      :dismissed
    else
      :unviewed
    end
  end

  def path_ownership
    Platform::Models::PathOwnership.new(
      codeowners: comparison.codeowners,
      diff: comparison.diff,
      path: path
    )
  end

  private

  def path
    path =
      if delta.is_a?(GitRPC::Diff::Delta)
        a = delta.old_file
        b = delta.new_file
        delta.deleted? ? a.path : b.path
      else
        delta.deleted? ? delta.a_path : @object.b_path
      end
    PullRequest.display_ref_name(path.dup)
  end
end
