# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    # Public: Validates if an actor/user and repo/organization have access to the Copilot code review feature.
    class CodeReviewUpsell
      include GitHub::Memoizer
      include GitHub::ResilienceMixin

      DISMISS_KEY_BASE = "DismissCopilotAssistedCodeReviewUpsell:V1"

      sig { params(actor: User, current_repository: Repository).void }
      def initialize(actor:, current_repository:)
        @actor = actor
        @repo = current_repository
      end

      sig { returns(T::Boolean) }
      memoize def show_ccr_upsell?
        return false if GitHub.enterprise?

        # Never show if the user has dismissed the upsell
        log("actor has #{dismissed? ? 'dismissed' : 'not dismissed'} the upsell banner")
        return false if dismissed?
        if @actor.feature_flag_enabled?(:copilot_assisted_review_upsell_defers_to_access, default: false)
          # Don't show if CodeReviewAccess would not suggest Copilot as a reviewer for this repository
          log("actor in repository #{would_suggest_copilot? ? 'could' : 'could not'} use copilot code review")
          return false unless would_suggest_copilot?
        else
          # Only shown for personally owned repositories
          log("actor #{@repo.owner == @actor ? 'owns' : 'does not own'} this repository")
          return false unless @repo.owner == @actor
        end
        # And they're on a free plan
        log("actor #{copilot_user.has_limited_access? ? 'has' : 'does not have'} limited access")
        return false unless copilot_user.has_limited_access?
        # And they're still eligible for a trial...
        log("actor #{copilot_user.eligible_for_trial? ? 'is' : 'is not'} eligible for a trial")
        return false unless copilot_user.eligible_for_trial?

        true
      end

      sig { returns(T::Boolean) }
      def dismissed?
        Users::Kv.store.exists(dismiss_key).value { false }
      end

      sig { void }
      def dismiss!
        Users::Kv.store.set(dismiss_key, "true")
      end

      sig { void }
      def reset!
        Users::Kv.store.del(dismiss_key)
      end

      private

      sig { returns(String) }
      memoize def dismiss_key
        "#{DISMISS_KEY_BASE}:#{@actor.id}"
      end

      sig { returns(::Copilot::User) }
      memoize def copilot_user
        ::Copilot::User.new(@actor)
      end

      sig { params(message: String).void }
      def log(message)
        PullRequests::Copilot::CodeReviewUpsellLogger.upsell_log(message, actor: @actor, repository: @repo)
      end

      sig { returns(PullRequests::Copilot::CodeReviewAccess) }
      memoize def code_review_access
        PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @repo)
      end

      sig { returns(T::Boolean) }
      memoize def would_suggest_copilot?
        with_database_error_fallback(fallback: false) do
          code_review_access.should_suggest_reviewer_for_repository?
        end
      end
    end
  end
end
