# typed: true
# frozen_string_literal: true

module Actions
  module Settings

    class CacheSizeLimitGhesComponent < ApplicationComponent
      include ActionsCacheHelper

      def initialize(entity:)
        @entity = entity
      end

      def update_cache_size_path
        if @entity.is_a?(Business)
          settings_actions_cache_size_limit_enterprise_path(@entity.slug)
        elsif @entity.is_a?(Organization)
          settings_org_actions_cache_size_path(@entity)
        else
          repo_actions_cache_size_path(repository: @entity, user_id: @entity.owner)
        end
      end

      def cache_size_limit_header
        return "Cache size limit" if @entity.is_a?(Repository)
        "Default cache size limit"
      end

      def cache_size_limit_description
        if @entity.is_a?(Repository)
          "Cache size limit for this repo"
        elsif @entity.is_a?(Organization)
          "Default cache size limit for repos in this organization"
        else
          "Default cache size limit for repos in this enterprise"
        end
      end

      memoize def value
        @entity.actions_cache_size_limit
      end

      memoize def upper_limit
        @entity.max_allowed_actions_cache_size_limit
      end
    end
  end
end
