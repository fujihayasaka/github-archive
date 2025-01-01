# typed: true
# frozen_string_literal: true

class Dependabot::CommentCreator
  Location = Struct.new(:file_path, :start_line, :end_line)

  def initialize(pull_request:, check_run:, reviewer:)
    @pull_request = pull_request
    @check_run = check_run
    @head_commit_oid = check_run.head_sha
    @reviewer = reviewer
  end

  def create_review_comments(location:)
    if head_commit_oid != pull_request.head_sha
      log(
        "Skipping review comment creation because analyzed commit is not the PR's head",
        "gh.pull_request.head_sha" => pull_request.head_sha
      )
      return
    end

    if pull_request.issue.locked?
      log "Pull request is locked - aborting review comment creation."
      return
    end

    pull_comparison = find_pull_comparison(head_commit_oid)
    if pull_comparison.nil?
      log("pull_comparison is nil - aborting review comment creation.",
        "gh.pull_request.merge_base" => pull_request.merge_base)
      return
    end

    review = pull_request.build_dependabot_variant_review do |r|
      r.user = reviewer
      r.head_sha = head_commit_oid
      r.merge_base_sha = pull_request.find_best_merge_base_sha(head_sha: head_commit_oid)
    end
    populate_review(review, location, pull_comparison)
  end

  private

  attr_reader :pull_request, :check_run, :head_commit_oid, :reviewer

  def populate_review(review, location, pull_comparison)
    review_comment = build_review_comment(review, pull_comparison, location)
    if review_comment.save
      review.comment!
    else
      filtered_errors = review_comment.errors.filter do |error|
        !(error.attribute == :"pull_request_review_thread.end_commit_oid" && error.type == "is not part of the pull request")
      end

      if filtered_errors.length > 0
        log("Validation errors while saving review comment",
            "gh.dependabot.validation_errors" => filtered_errors,
           )
        raise ActiveRecord::RecordInvalid.new(review_comment)
      end
    end
  end

  def build_review_comment(review, pull_comparison, location)
    thread = review.build_thread

    attributes = {
      user: review.user,
      diff: pull_comparison.diffs,
      body: "Dependabot detected a breaking change in this pull request.",
      path: location.file_path,
      line: location.end_line,
      side: :right,
    }

    # seems unlikely for Dependabot to ever comment on a multi-line diff, as
    # we're always targeting a change in the lockfile, which tend to be single
    # line changes.
    if location.start_line != location.end_line
      attributes.merge!(start_line: location.start_line, start_side: :right)
    end

    thread.build_first_comment(**attributes)
  end

  def find_pull_comparison(commit_oid)
    PullRequest::Comparison.find(
      pull: pull_request,
      start_commit_oid: pull_request.merge_base,
      end_commit_oid: commit_oid,
      base_commit_oid: pull_request.merge_base,
    )
  end

  def log(msg, other_log_params = {})
    calling_method = caller_locations(1, 1)&.first&.base_label

    GitHub.logger.info(msg,
      "code.namespace" => "CreateDependabotAnnotationsJob",
      "code.function" => calling_method,
      "gh.repo.id" => check_run.repository&.id,
      "gh.check_run.id" => check_run&.id,
      "gh.pull_request.id" => pull_request.id,
      **other_log_params
    )
  end
end
