# typed: true
# frozen_string_literal: true

module Search
  module Filters
    # A filter that excludes draft PRs authored by Copilot unless the current user is an assignee
    class CopilotDraftExclusionFilter < ::Search::Filter

      sig { params(current_user: T.nilable(User)).void }
      def initialize(current_user:)
        @current_user = T.let(current_user, T.nilable(User))
        @copilot_bot_id = Bot.find_by_slug(Apps::Privileged::CopilotSWEAgent::SLUG)&.id
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def must_not
        # Base conditions: draft PRs authored by Copilot
        conditions = T.let([
          { term: { draft: true } },
          { term: { author_id: @copilot_bot_id } }
        ], T::Array[T::Hash[Symbol, T.untyped]])

        # If user is present, add condition to exclude when they are assignee
        if @current_user.present?
          conditions << {
            bool: {
              must_not: [{ term: { assignee_id: @current_user.id } }]
            }
          }
        end

        [{
          bool: {
            must: conditions
          }
        }]
      end

      sig { returns(T::Boolean) }
      def nil?
        @copilot_bot_id.nil?
      end

      sig { returns(T::Boolean) }
      def valid?
        @copilot_bot_id.present?
      end

      sig { returns(T::Boolean) }
      def blank?
        !valid?
      end

      sig { returns(String) }
      def invalid_reason
        "No Copilot user found"
      end
    end
  end
end
