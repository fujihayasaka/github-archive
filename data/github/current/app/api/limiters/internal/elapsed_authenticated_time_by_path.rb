# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    module Internal
      class ElapsedAuthenticatedTimeByPath < Api::Limiters::Internal::ElapsedTimeByAuthenticationFingerprint
        attr_reader :path

        LIMITER_LOG_PREFIX = "internal.elapsed"

        def initialize(name:, max:, path:)
          super(name, max: max)
          @path = path
        end

        def ignored?(request)
          return true unless request.path_info == path
          # The rest of the ignore logic is the same as the parent class. This also ensure that all feature flags
          # in the inheritance chain are also checked
          super(request)
        end

        def record_finish(request)
          return OK if ignored?(request)
          increment_counter(request)
        end

        protected

        def key(request)
          [super, path.parameterize].join(":")
        end
      end
    end
  end
end
