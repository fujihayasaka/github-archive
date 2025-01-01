# typed: true
# frozen_string_literal: true

class Hovercards::CopilotController < ApplicationController
  before_action :require_xhr, only: [:show]

  PERMITTED_SLUGS = [
    Apps::Privileged::CopilotPullRequestReviewer::SLUG,
  ]

  def show
    show_internal
  end

  private

  def show_internal
    return render_404 unless this_bot

    render Hovercards::Bots::BotCardHandlerComponent.new(bot: this_bot), layout: false
  end

  memoize def this_bot
    user_login = params[:bot]

    return unless user_login.present?
    return unless PERMITTED_SLUGS.include?(user_login)

    @this_bot = Bot.find_by_slug(user_login)
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
