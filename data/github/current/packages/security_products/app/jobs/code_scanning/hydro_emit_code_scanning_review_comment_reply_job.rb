# typed: true
# frozen_string_literal: true

class CodeScanning::HydroEmitCodeScanningReviewCommentReplyJob < HydroMessageJob
  extend T::Sig
  include Scientist

  queue_as :hydro_emit_code_scanning_review_comment_reply

  retry_on_dirty_exit

  # Public: Emits a Hydro event for a reply to a code scanning review comment.
  sig { void }
  def perform
    return if message.nil? || message[:pull_request_review_thread].nil?

    # verify this comment is a reply
    return unless PullRequestReviewComment.where(id: message[:pull_request_review_comment][:id]).where.not(reply_to_id: nil).exists?

    user_id = PullRequestReviewThread.select(:id).find_by(id: message[:pull_request_review_thread][:id])&.review_comments&.pick(:user_id)
    return unless user_id == self.class.code_scanning_bot_id

    GlobalInstrumenter.instrument("code_scanning.pull_request_review_comment_reply", message)
  end

  def self.code_scanning_bot_id
    # only cache the value if it is not nil so we can try refetching it if it was not found for some reason
    # ideally we would get the bot_id from the `integrations` table here but the latency on mysql1 is so high
    # we have to query users instead
    @code_scanning_bot_id ||= Bot.find_by_login(Apps::Internal::CodeScanning::GHAS_BOT_LOGIN)&.id # rubocop:disable GitHub/BooleanMemoizationWithOrOperator
  end
end
