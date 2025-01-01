# typed: true
# frozen_string_literal: true

module Actions
  module Settings

    class MaximumCacheSizeLimitComponent < ApplicationComponent
      include ActionsCacheHelper

      def initialize(entity:)
        @entity = entity
      end

      def update_maximum_cache_size_path
        settings_actions_cache_size_upper_limit_enterprise_path(@entity.slug)
      end

      memoize def value
        @entity.max_allowed_actions_cache_size_limit
      end

      memoize def upper_limit
        99999
      end

    end
  end
end
