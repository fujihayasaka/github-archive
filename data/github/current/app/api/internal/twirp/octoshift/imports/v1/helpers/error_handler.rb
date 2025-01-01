# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      module Helpers
        module ErrorHandler
          def save_model_error_handler(model)
            return Twirp::Error.resource_exhausted(
              "Could not create #{model.class.name} due to content creation rate limits",
              octoshift_error_code: "RATE_LIMIT_EXCEPTION"
            ) if model.errors.full_messages.detect { |m| m.include?("was submitted too quickly") }
            return Twirp::Error.resource_exhausted(
              "#{model.class.name} attempted to load, but already exists",
              octoshift_error_code: "ALREADY_EXISTS"
            ) if model.errors.full_messages.detect { |m| m.include?("Duplicate entry") }
            return Twirp::Error.invalid_argument(
              "Could not create #{model.class.name}: #{model.errors.full_messages.join(", ")}",
              octoshift_error_code: "REVIEW_THREAD_MISSING_BODY"
            ) if model.errors.full_messages.detect { |m| m.include?("Body required") }

            Twirp::Error.invalid_argument("Could not create #{model.class.name}: #{model.errors.full_messages.join(", ")}")
          end

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
        end
      end
    end
  end
end
