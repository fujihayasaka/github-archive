# typed: true
# frozen_string_literal: true

class HydroEmitCodeScanningReviewUnresolveJob < HydroMessageJob
  queue_as :hydro_emit_code_scanning_review_unresolve

  retry_on_dirty_exit

  # Public: process a Hydro message
  sig { void }
  def perform
    thread = PullRequestReviewThread.find_by(id: message[:pull_request_review_thread][:id])
    return unless thread
    return if thread.review_comments.empty?

    first_comment = T.must(thread.review_comments.first)
    return unless first_comment.user&.bot?
    return unless T.cast(first_comment.user, Bot).slug == Apps::Privileged::CodeScanning::GHAS_BOT_LOGIN

    GlobalInstrumenter.instrument("code_scanning.pull_request_review_comment_unresolve", message)
  end
end
