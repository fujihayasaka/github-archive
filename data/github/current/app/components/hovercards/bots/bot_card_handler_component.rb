# typed: true
# frozen_string_literal: true

module Hovercards
  module Bots
    class BotCardHandlerComponent < ApplicationComponent

      sig { params(bot: T.untyped).void }
      def initialize(bot:)
        @bot = bot
        @slug = @bot&.slug
      end

      sig { returns(T.untyped) }
      def call
        case @slug
        when ::Apps::Privileged::CopilotPullRequestReviewer::SLUG
          render partial: "hovercards/copilot/reviewer", locals: { bot: @bot }
        else
          raise NotImplementedError, "No hovercard for bot: #{@slug}"
        end
      end
    end
  end
end
