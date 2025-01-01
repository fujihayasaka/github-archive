# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      module Helpers
        module ContentCreation
          MAX_THROTTLE_RETRIES = 5.freeze

          def rate_limited_mode(model, throttle: true)
            if throttle
              model.class.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, skip_reporting: true) do
                create_content(model) do
                  yield
                end
              end
            else
              create_content(model) do
                yield
              end
            end
          end

          def create_content(model)
            ActiveRecord::Base.connected_to(role: :writing) do
              if disable_rate_limit_configuration?
                GitHub::RateLimitedCreation.disable_content_creation_rate_limits do
                  yield
                end
              else
                yield
              end
            end
          end

          def disable_rate_limit_configuration?
            return @disable_rate_limit_configuration if defined?(@disable_rate_limit_configuration)
            @disable_rate_limit_configuration = \
              GitHub.flipper[:octoshift_importable_creation_rate_limits].enabled?
          end
        end
      end
    end
  end
end
