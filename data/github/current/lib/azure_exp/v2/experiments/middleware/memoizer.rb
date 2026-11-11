# typed: strict
# frozen_string_literal: true

module AzureEXP
  module V2
    module Experiments
      module Middleware
        # Rack middleware that manages the AzureEXP::V2::Experiments request lifecycle.
        #
        # On each request:
        # 1. Ensures AzureEXP::V2::Experiments.current is initialized (via ActiveSupport::CurrentAttributes)
        # 2. After authentication, seeds the user-level participant
        #
        # ActiveSupport::CurrentAttributes handles cleanup between requests
        # automatically, so no explicit teardown is needed.
        #
        # Mirror of FeatureFlag::Middleware::Memoizer for the experiments system.
        class Memoizer
          extend T::Helpers

          sig { params(app: T.untyped).void }
          def initialize(app)
            @app = T.let(app, T.untyped)
          end

          sig { params(env: T::Hash[T.any(String, Symbol), T.untyped]).returns(T::Array[T.untyped]) }
          def call(env)
            # Ensure the context exists for this request.
            # The actual user seeding happens post-auth via an
            # after_authentication hook (not in this middleware),
            # because we don't know the user at Rack level.
            AzureEXP::V2::Experiments.current

            @app.call(env)
          end
        end
      end
    end
  end
end
