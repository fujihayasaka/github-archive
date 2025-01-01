# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      module Helpers
        module ErrorHandler
          include Imports::Helpers::ErrorHandler

          def save_model_error_handler(model)
            error = extract_model_error(model)
            twirp_error_code = error[:twirp_error_code]
            octoshift_error_code = error[:octoshift_error_code]
            message = error[:message]

            case twirp_error_code
            when "resource_exhausted"
              Twirp::Error.resource_exhausted(message, octoshift_error_code: octoshift_error_code)
            when "invalid_argument"
              Twirp::Error.invalid_argument(message, octoshift_error_code: octoshift_error_code)
            when "already_exists"
              Twirp::Error.already_exists(message, octoshift_error_code: octoshift_error_code)
            else
              Twirp::Error.unknown(message, octoshift_error_code: octoshift_error_code)
            end
          end
        end
      end
    end
  end
end
