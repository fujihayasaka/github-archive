# typed: strict
# frozen_string_literal: true

module OctoCore
  module Api
    module ErrorHandling
      extend T::Helpers
      extend T::Sig

      include ActionController::Rendering

      private

      # :errors no longer supports ActiveModel::Errors.
      # Use OctoCore::Api::ActiveModelErrorConverter.convert_error upstream of this method
      # if you still rely on ActiveModel::Errors.
      sig do
        params(
          status: Integer,
          message: T.nilable(String),
          errors: T.nilable(T::Array[String]),
          documentation_url: T.nilable(String)
        ).void
      end
      def deliver_error(status, message: nil, errors: nil, documentation_url: nil)
        error_resp = error_response(status, message:, errors:, documentation_url:)
        render json: error_resp, status: status
      end

      sig do
        params(
          status: Integer,
          message: T.nilable(String),
          errors: T.nilable(T::Array[T.untyped]),
          documentation_url: T.nilable(String)
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def error_response(status, message: nil, errors: nil, documentation_url: nil)
        {
          status: status.to_s,
          errors:,
          documentation_url: documentation_url || OctoCore::Api::DOCS_BASE_URL,
          message: message || default_error_status_message(status)
        }.compact
      end

      sig { params(status: Integer).returns(String) }
      def default_error_status_message(status)
        case status
        when 404 then "Not Found"
        when 400 then "Bad Request"
        when 401 then "Requires authentication"
        when 403 then "Rate Limit Exceeded"
        when 409 then "Conflict"
        when 415 then "Unsupported Media Type"
        when 422 then "Validation Failed"
        when 301 then "Moved Permanently"
        when 302 then "Found"
        else          "Server Error"
        end
      end
    end
  end
end
