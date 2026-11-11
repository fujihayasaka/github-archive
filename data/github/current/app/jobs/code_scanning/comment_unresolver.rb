# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# CommentUnresolver is used by CreateCodeScanningAnnotationsJob
# to unresolve comments on Pull Requests.
class CodeScanning::CommentUnresolver

  def initialize(pull_request:, head_commit_oid:, merge_commit_oid:)
    @pull_request = pull_request
    @head_commit_oid = head_commit_oid
    @merge_commit_oid = merge_commit_oid
  end

  def manage_unfixed_comments(alerts, unresolver)
    @base_logger_attributes =
      {
        "code.namespace" => "CreateCodeScanningAnnotationsJob",
        "code.function" => "manage_unfixed_comments",
        "gh.repo.id" => @pull_request.repository_id,
        "gh.pull_request.id" => @pull_request&.id,
        "gh.pull_request.head_sha" => @head_commit_oid,
        "gh.pull_request.merge_sha" => @merge_commit_oid,
      }

    alert_numbers = alerts.map(&:number)
    comments_to_unresolve = @pull_request.code_scanning_review_comments.where(fixed: true, alert_number: alert_numbers)
    comments_to_unresolve.each do |csrc|
      reopen_code_scanning_review_comment(csrc)
      unresolve_comment_thread(csrc, unresolver)
    end
  end

  private

  def reopen_code_scanning_review_comment(csrc)
    ActiveRecord::Base.connected_to(role: :writing) do
      csrc.reopen!
    end
    GitHub.logger.info(
      "We have reopened this code scanning review comment",
      @base_logger_attributes.merge({ "gh.code_scanning.review_comment.id" => csrc.id })
    )
  end

  def unresolve_comment_thread(csrc, unresolver)
    comment = csrc.pull_request_review_comment
    if comment.present?
      thread = comment.pull_request_review_thread
      if thread.conversation?
        ActiveRecord::Base.connected_to(role: :writing) do
          thread.unresolve(unresolver: unresolver)
        end
        GitHub.logger.info("Unresolving conversation for reopened code scanning alert",
          @base_logger_attributes.merge({ "gh.code_scanning.review_comment.id" => csrc.id })
        )
      end
    else
      GitHub.logger.info("PullRequestReviewComment missing",
        @base_logger_attributes.merge({ "gh.code_scanning.review_comment.id" => csrc.id })
      )
    end
  end
end
