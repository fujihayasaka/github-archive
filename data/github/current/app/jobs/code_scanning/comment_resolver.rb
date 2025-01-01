# typed: true
# frozen_string_literal: true

# CommentResolver is used by CreateCodeScanningAnnotationsJob
# to resolve comments on Pull Requests.
class CodeScanning::CommentResolver
  attr_reader :pull, :head_commit_oid, :merge_commit_oid

  def initialize(pull, head_commit_oid, merge_commit_oid)
    @pull = pull
    @head_commit_oid = head_commit_oid
    @merge_commit_oid = merge_commit_oid
  end

  def manage_fixed_comments(resolver:)
    cs_review_comments = unfixed_code_scanning_review_comments_by_number(pull)
    return if cs_review_comments.empty?

    # We need to remove comments only for alerts that are fixed in the commit the check run in this job is for.
    # cs_review_comments may still contain alerts that are not fixed because e.g. they may be from a tool
    # other than the one this check run is about, or they may have been dismissed which makes them not appear in
    # the diff response.
    results = GitHub::Turboscan.annotations(
      repository_id: pull.repository_id,
      numbers: cs_review_comments.keys,
      merge_commit_oid: merge_commit_oid,
      head_commit_oid: head_commit_oid,
    )&.data&.results&.map { |result| result.result } || []
    # we can't interpret alerts not included in the response as being fixed because this can cause a race condition: if
    # the latest analysis for a different tool/configuration hasn't been processed yet then asking for annotations from that
    # commit won't return any results for alerts that correspond to that analysis.
    fixed_alerts = results.select { |result| result.most_recent_instance&.is_fixed }.map { |result| result.number }
    fixed_comments = cs_review_comments.select { |number, _| fixed_alerts.include?(number) }.map { |_, comment| comment }
    fixed_comments.each do |csrc|
      fix_code_scanning_review_comment(csrc)
      resolve_comment_thread(csrc, resolver)
    end
  end

  private

  def unfixed_code_scanning_review_comments_by_number(pull)
    pull.code_scanning_review_comments.inject(Hash.new) do |h, comment|
      h[comment.alert_number] ||= comment if !comment.fixed
      h
    end
  end

  def fix_code_scanning_review_comment(csrc)
    ActiveRecord::Base.connected_to(role: :writing) do
      csrc.fix!
    end
    log(code_scanning_review_comment: csrc, msg: "We have marked this code scanning review comment as fixed")
  end

  def resolve_comment_thread(csrc, resolver)
    comment = csrc.pull_request_review_comment
    if comment.present?
      thread = comment.pull_request_review_thread
      if thread.conversation?
        ActiveRecord::Base.connected_to(role: :writing) do
          thread.resolve(resolver: resolver)
        end
        log(code_scanning_review_comment: csrc, msg: "Autoresolving conversation for fixed code scanning alert")
      end
    else
      log(code_scanning_review_comment: csrc, msg: "PullRequestReviewComment missing")
    end
  end

  def log(code_scanning_review_comment:, msg:)
    GitHub.logger.info(
      msg,
      "code.namespace" => "CreateCodeScanningAnnotationsJob",
      "code.function" => "manage_fixed_comments",
      "gh.repo.id" => pull.repository_id,
      "gh.pull_request.id" => pull&.id,
      "gh.pull_request.head_sha" => head_commit_oid,
      "gh.pull_request.merge_sha" => merge_commit_oid,
      "gh.code_scanning.review_comment.id" => code_scanning_review_comment.id)
  end
end
