# typed: true
# frozen_string_literal: true

module Actions
  module Settings

    class RetentionComponent < ApplicationComponent
      include ActionsCacheHelper

      DEFAULT = "Default".freeze
      MAXIMUM = "Maximum".freeze

      def initialize(entity:, update_retention_limit_path:)
        @entity = entity
        @update_retention_limit_path = update_retention_limit_path
      end

      def render?
        return @entity.can_write_organization_actions_settings?(current_user) if @entity.is_a?(Organization)
        true
      end

      def header
        return "Artifact, log, and cache settings" if show_ghes_cache_size_policy?
        "Artifact and log retention"
      end

      def description
        if show_ghes_cache_size_policy?
          return "Choose the repository settings for artifacts, logs, and caches." if @entity.is_a?(Repository)
          return "Choose the default repository settings for artifacts, logs, and caches." if @entity.is_a?(Organization)
          return "Choose the default organization settings for all artifacts, logs, and caches. Organizations cannot set a default limit above the maximum." if @entity.is_a?(Business)
        end
        return "Choose the repository settings for artifacts and logs." if @entity.is_a?(Repository)
        return "Choose the default repository settings for artifacts and logs." if @entity.is_a?(Organization)
        "Choose the default organization settings for artifacts and logs. Organizations can set a shorter duration, but not a longer one."
      end

      memoize def upper_limit_artifact_and_logs_retention
        @entity.max_allowed_actions_retention_limit
      end

      def artifact_log_retention_policy_url
        "#{GitHub.help_url}/actions/learn-github-actions/usage-limits-billing-and-administration#artifact-and-log-retention-policy"
      end

      def limit_description_start
        "Your #{owner_type} administrator has set a maximum limit of "
      end

      def show_limit_description?
        # if there is an configuration-owner-imposed upper limit, show explanition in description
        owner_restricted_upper_limit?
      end

      def owner_type
        @entity.is_a?(Repository) ? "organization" : "enterprise"
      end

      def owner_text
        if @entity.is_a?(Repository)
          if @entity.owner.is_a?(Organization)
            "Your organization has set"
          elsif GitHub.enterprise?
            "Your enterprise has set"
          else
            "There is"
          end
        else
          "Your enterprise has set"
        end
      end

      private

      def owner_restricted_upper_limit?
        # upper_limit is not the max we allow for this entity. It is restricted by a configuration owner.
        upper_limit_artifact_and_logs_retention != @entity.entity_type_max_retention_limit
      end
    end
  end
end
