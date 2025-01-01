# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ProtectedBranchSerializer < BaseSerializer
      def scope
        ProtectedBranch.preload(
          :creator,
          :repository,
          :required_status_checks,
        )
      end

      def as_json(options = {})
        {
          type:                                     "protected_branch",
          name:                                     name,
          url:                                      url,
          creator_url:                              creator_url,
          repository_url:                           repository_url,
          admin_enforced:                           admin_enforced,
          block_deletions_enforcement_level:        block_deletions_enforcement_level,
          block_force_pushes_enforcement_level:     block_force_pushes_enforcement_level,
          dismiss_stale_reviews_on_push:            dismiss_stale_reviews_on_push,
          pull_request_reviews_enforcement_level:   pull_request_reviews_enforcement_level,
          require_code_owner_review:                require_code_owner_review,
          required_status_checks_enforcement_level: required_status_checks_enforcement_level,
          strict_required_status_checks_policy:     strict_required_status_checks_policy,
          authorized_actors_only:                   authorized_actors_only,
          authorized_user_urls:                     authorized_user_urls,
          authorized_team_urls:                     authorized_team_urls,
          dismissal_restricted_user_urls:           dismissal_restricted_user_urls,
          dismissal_restricted_team_urls:           dismissal_restricted_team_urls,
          required_status_checks:                   required_status_checks,
          requires_approving_reviews:               requires_approving_reviews,
          required_approving_review_count:          required_approving_review_count,
          requires_commit_signatures:               requires_commit_signatures,
          requires_linear_history:                  requires_linear_history,
          blocks_creations:                         blocks_creations,
          allows_force_pushes:                      allows_force_pushes,
          allows_deletions:                         allows_deletions,
          requires_status_checks:                   requires_status_checks,
          restricts_review_dismissals:              restricts_review_dismissals,
          requires_review_thread_resolution:        requires_review_thread_resolution,
          require_last_push_approval:               require_last_push_approval
        }
      end

      private

      delegate(
        :admin_enforced,
        :authorized_actors_only,
        :authorized_teams,
        :authorized_users,
        :dismissal_restricted_users,
        :dismissal_restricted_teams,
        :dismiss_stale_reviews_on_push,
        :pull_request_reviews_enforcement_level,
        :require_code_owner_review,
        :required_status_checks_enforcement_level,
        :strict_required_status_checks_policy,
        :required_approving_review_count,
        :require_last_push_approval,
        to: :model,
      )

      def name
        model.name
      end

      def creator_url
        url_for_model(model.creator)
      end

      def repository_url
        url_for_model(model.repository)
      end

      def required_status_checks
        model.required_status_checks.map(&:context)
      end

      def authorized_user_urls
        model.authorized_users.map do |user|
          url_for_model(user)
        end
      end

      def authorized_team_urls
        model.authorized_teams.map do |team|
          url_for_model(team)
        end
      end

      def dismissal_restricted_user_urls
        model.dismissal_restricted_users.map do |user|
          url_for_model(user)
        end
      end

      def dismissal_restricted_team_urls
        model.dismissal_restricted_teams.map do |team|
          url_for_model(team)
        end
      end

      # Serialize :block_force_pushes_enforcement_level as a Fixnum to maintain backwards compatibility.
      def block_force_pushes_enforcement_level
        ProtectedBranch.block_force_pushes_enforcement_levels[model.block_force_pushes_enforcement_level]
      end

      # Serialize :block_deletions_enforcement_level as a Fixnum to maintain backwards compatibility.
      def block_deletions_enforcement_level
        ProtectedBranch.block_deletions_enforcement_levels[model.block_deletions_enforcement_level]
      end

      def requires_approving_reviews
        model.pull_request_reviews_enabled?
      end

      def requires_commit_signatures
        model.required_signatures_enabled?
      end

      def requires_linear_history
        model.required_linear_history_enabled?
      end

      def blocks_creations
        model.create_protected_enabled?
      end

      def allows_force_pushes
        !model.block_force_pushes_enabled?
      end

      def allows_deletions
        !model.block_deletions_enabled?
      end

      def requires_status_checks
        model.required_status_checks_enabled?
      end

      def restricts_review_dismissals
        model.restricted_dismissed_reviews?
      end

      def requires_review_thread_resolution
        model.required_review_thread_resolution_enabled?
      end
    end
  end
end
