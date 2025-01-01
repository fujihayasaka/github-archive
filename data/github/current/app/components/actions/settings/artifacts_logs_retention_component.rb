# typed: true
# frozen_string_literal: true

module Actions
  module Settings

    class ArtifactsLogsRetentionComponent < ApplicationComponent
      def initialize(entity:, update_retention_limit_path:)
        @entity = entity
        @update_retention_limit_path = update_retention_limit_path
      end

      memoize def upper_limit
        @entity.max_allowed_actions_retention_limit
      end

      memoize def value
        @entity.actions_retention_limit
      end

      def upper_limit_error
        return "Duration must be #{upper_limit} or less" unless owner_restricted_upper_limit?
        owner_type = @entity.is_a?(Repository) ? "organization" : "enterprise"
        "The #{owner_type} has set a maximum duration of #{upper_limit} days"
      end

      private

      def owner_restricted_upper_limit?
        # upper_limit is not the max we allow for this entity. It is restricted by a configuration owner.
        upper_limit != @entity.entity_type_max_retention_limit
      end
    end
  end
end
