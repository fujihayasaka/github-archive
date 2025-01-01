# typed: true
# frozen_string_literal: true

class Hovercards::CopilotController < ApplicationController
  before_action :require_xhr, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    only: [:show]

  PERMITTED_SLUGS = [
    Apps::Privileged::CopilotPullRequestReviewer::SLUG,
    Apps::Privileged::CopilotSWEAgent::SLUG,
  ]

  def show
    show_internal
  end

  private

  def show_internal
    return render_404 unless this_bot

    render Hovercards::Bots::BotCardHandlerComponent.new(bot: this_bot, has_code_review_access: has_code_review_access?), layout: false
  end

  memoize def this_bot
    user_login = params[:bot]

    return unless user_login.present?
    return unless PERMITTED_SLUGS.include?(user_login)

    @this_bot = Bot.find_by_slug(user_login)
  end

  memoize def has_code_review_access?
    _, id = params[:subject]&.split(":")
    pull_request = PullRequest.find_by(id: id.to_i)
    return false unless pull_request.present?

    code_review_access = PullRequests::Copilot::CodeReviewAccess.new(actor: current_user, current_repository: T.must(pull_request.repository))
    code_review_access.can_create_review_request?
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
