# typed: true
# frozen_string_literal: true

module PullRequests::CanRequestBotReviewHelper
  def can_request_bot_review(current_user, review_user, current_repository)
    if current_user.nil? || review_user.nil? || current_repository.nil?
      return false
    end

    # human users should be allowed at this stage
    if review_user.is_a?(User) && !review_user.is_a?(Bot)
      return true
    end

    # make sure the bot is the copilot reviewer bot, other bots aren't allowed yet
    reviewer_app = Apps::Privileged.integration(:copilot_pull_request_reviewer)
    if !reviewer_app.present? || reviewer_app.bot.id != review_user.id
      return false
    end

    # finally, make sure the user has access to the copilot reviewer bot
    access = PullRequests::Copilot::CodeReviewAccess.new(actor: current_user, current_repository: current_repository)
    access.can_create_review_request?
  end
end
