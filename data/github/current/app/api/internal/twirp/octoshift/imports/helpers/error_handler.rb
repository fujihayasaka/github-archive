# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module Helpers
      module ErrorHandler
        def rate_limit_error_handler(error)
          return Twirp::Error.resource_exhausted(
            "Could not create resource due to content creation rate limits",
            octoshift_error_code: "RATE_LIMIT_EXCEPTION"
          ) if error.msg.include?("was submitted too quickly")
          error
        end

        def already_exists_error_handler(class_name)
          Twirp::Error.already_exists(
            "#{class_name} attempted to load, but already exists",
            octoshift_error_code: "ALREADY_EXISTS"
          )
        end

        def replication_delay_error_handler(delay, role)
          Twirp::Error.failed_precondition(
            "Request cannot be fulfilled due to replication delay.",
            octoshift_error_code: "FRENO_REPLICATION_DELAY", delay: delay.to_s, role: role.to_s
          )
        end

        # Extracts errors from the model and returns a hash of
        # twirp_error_code, octoshift_error_code and the error message
        def extract_model_error(model)
          if model.errors.full_messages.detect { |m| m.include?("was submitted too quickly") }
            return {
              twirp_error_code: "resource_exhausted",
              octoshift_error_code: "RATE_LIMIT_EXCEPTION",
              message: "Could not create #{model.class.name} due to content creation rate limits"
            }
          end

          if model.errors.full_messages.detect { |m| m.include?("Duplicate entry") }
            return {
              twirp_error_code: "already_exists",
              octoshift_error_code: "ALREADY_EXISTS",
              message: "#{model.class.name} attempted to load, but already exists"
            }
          end

          if model.errors.full_messages.detect { |m| m.include?("Body required") }
            return {
              twirp_error_code: "invalid_argument",
              octoshift_error_code: "REVIEW_THREAD_MISSING_BODY",
              message: "Could not create #{model.class.name}: #{model.errors.full_messages.join(", ")}"
            }
          end

          {
            twirp_error_code: "invalid_argument",
            octoshift_error_code: "",
            message: "Could not create #{model.class.name}: #{model.errors.full_messages.join(", ")}"
          }
        end
      end
    end
  end
end
