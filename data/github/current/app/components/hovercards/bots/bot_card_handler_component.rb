# typed: true
# frozen_string_literal: true

module Hovercards
  module Bots
    class BotCardHandlerComponent < ApplicationComponent

      sig { params(bot: T.untyped, has_code_review_access: T.nilable(T::Boolean)).void }
      def initialize(bot:, has_code_review_access: false)
        @bot = bot
        @slug = @bot&.slug
        @has_code_review_access = has_code_review_access
      end

      sig { returns(T.untyped) }
      def call
        case @slug
        when ::Apps::Privileged::CopilotPullRequestReviewer::SLUG
          render partial: "hovercards/copilot/reviewer", locals: { bot: @bot, has_code_review_access: @has_code_review_access }
        when ::Apps::Privileged::CopilotSWEAgent::SLUG
          render partial: "hovercards/copilot/swe_agent", locals: { bot: @bot }
        else
          raise NotImplementedError, "No hovercard for bot: #{@slug}"
        end
      end
    end
  end
end
