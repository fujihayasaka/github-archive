# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    # Public: Validates if an actor/user and repo/organization have access to the Pull Request Groups feature
    class PullRequestGroupsAccess
      include GitHub::Memoizer
      include GitHub::ResilienceMixin

      class Reason < T::Struct
        const :access, T::Boolean, default: false
        const :reason, Symbol

        sig { returns(T.attached_class) }
        def self.eligible = new(access: true, reason: :eligible)

        sig { returns(T.attached_class) }
        def self.actor_ineligible = new(access: false, reason: :actor_ineligible)

        sig { returns(T.attached_class) }
        def self.feature_not_enabled = new(access: false, reason: :feature_not_enabled)

        sig { params(other: Object).returns(T::Boolean) }
        def ==(other)
          return false unless other.is_a?(self.class)
          access == other.access && reason == other.reason
        end
      end

      sig { params(actor: T.nilable(User), current_repository: T.nilable(Repository), pull_request: T.nilable(PullRequest)).void }
      def initialize(actor:, current_repository:, pull_request: nil)
        @actor = actor
        @repo = current_repository
        @pull_request = pull_request
      end

      # Public: Returns whether generating pull request groups is enabled
      sig { returns(T::Boolean) }
      def can_generate_automatic_groups?
        can_generate_automatic_groups_reason.access
      end

      # Public: Returns whether generating pull request groups is enabled reason
      sig { returns(PullRequestGroupsAccess::Reason) }
      def can_generate_automatic_groups_reason
        return Reason.eligible if actor_feature_enabled?(:pull_request_groups_full_access)

        return Reason.feature_not_enabled unless actor_feature_enabled?(:generate_pull_request_groups)

        return Reason.actor_ineligible unless actor_eligible?

        Reason.eligible
      end

      # Public: Returns whether viewing generated pull request groups is enabled
      sig { returns(T::Boolean) }
      def can_view_generated_groups?
        can_view_generated_groups_reason.access
      end

      private

      # Private: Returns whether viewing generated pull request groups is enabled reason
      sig { returns(PullRequestGroupsAccess::Reason) }
      def can_view_generated_groups_reason
        return Reason.eligible if actor_feature_enabled?(:pull_request_groups_full_access)

        return Reason.feature_not_enabled unless actor_feature_enabled?(:pull_request_groups_ui)

        return Reason.actor_ineligible unless actor_eligible?

        Reason.eligible
      end

      sig { params(message: String).void }
      def log(message)
        GitHub.logger.info("copilot_pull_request_groups_access: #{message}",
          "gh.repo.id" => @repo&.name,
          "gh.user.id" => @actor&.id,
          "gh.user.login" => @actor&.display_login,
          "gh.pull_request.id" => @pull_request&.id,
        )
      end

      sig { returns(T::Boolean) }
      def actor_eligible?
        log("checking if actor is eligible")

        with_database_error_fallback(fallback: false) do
          return false unless copilot_user&.has_copilot_access?
          return false unless copilot_user&.has_pro_plus_access? || copilot_user&.has_ce_access?
          true
        end
      end

      # Private: Checks if a feature is enabled for the actor.
      sig { params(feature: Symbol).returns(T::Boolean) }
      private def actor_feature_enabled?(feature)
        return false if @actor.nil?
        @actor.feature_flag_enabled?(feature, default: false)
      end

      sig { returns(T.nilable(::Copilot::Public::User)) }
      private memoize def copilot_user
        return nil unless @actor.is_a?(User)
        ::Copilot::Public::User.new(@actor)
      end
    end
  end
end
