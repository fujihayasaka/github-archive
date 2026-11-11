# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module V2
      module Helpers
        module ErrorHandler
          include Imports::Helpers::ErrorHandler

          def save_model_error_handler(model, resource_identifier)
            error = extract_model_error(model)
            twirp_error_code = error[:twirp_error_code]
            octoshift_error_code = error[:octoshift_error_code]
            message = error[:message]

            build_error_hash(
              resource_identifier: resource_identifier,
              message: message,
              twirp_error_code: twirp_error_code,
              octoshift_error_code: octoshift_error_code
            )
          end

          def build_error_hash(resource_identifier: nil,  message:, twirp_error_code: nil, octoshift_error_code: nil)
            {
              resource_identifier: resource_identifier,
              message: message,
              twirp_error_code: twirp_error_code,
              octoshift_error_code: octoshift_error_code
            }
          end
        end
      end
    end
  end
end
