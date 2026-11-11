# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class Domain
    class Failures < GH::Domain::Base
      ENABLEMENT_FAILURES_JSON_PATH = T.let(
        Rails.root.join("config", "code_security_configuration_failures.json"),
        Pathname
      )

      # Returns all known failure reason keys.
      sig { returns(T::Array[String]) }
      def reasons
        failures_map.keys
      end

      # Returns the failure configuration for a specific reason, or nil if not found.
      sig { params(reason: T.nilable(String)).returns(T.nilable(T::Hash[String, T.untyped])) }
      def for(reason)
        return nil if reason.nil?

        failures_map[reason]
      end

      # Checks if a failure reason is known/handled.
      sig { params(reason: T.nilable(String)).returns(T::Boolean) }
      def known?(reason)
        return false if reason.nil?

        failures_map.key?(reason)
      end

      # Returns the frontend banner reason for a failure, falling back to "Unknown" if not found.
      sig { params(reason: T.nilable(String)).returns(T.nilable(String)) }
      def banner_reason_for(reason)
        if reason
          failures_map.dig(reason, "frontend_banner_reason") ||
            failures_map.dig("Unknown", "frontend_banner_reason")
        else
          failures_map.dig("Unknown", "frontend_banner_reason")
        end
      end

      # Checks if audit logging is allowed for a failure reason.
      sig { params(reason: String).returns(T::Boolean) }
      def audit_log_allowed?(reason)
        failures_map.dig(reason, "audit_log_allowed") != false
      end

      # Returns the audit log message for a failure reason, or a default message if not allowed.
      sig { params(reason: T.nilable(String)).returns(String) }
      def audit_log_message_for(reason)
        return "Failed to enable." if reason.nil?

        failure = failures_map[reason]
        return failure["audit_log_message"] if failure && failure["audit_log_allowed"]

        "Failed to enable."
      end

      # Returns a map of filter tokens to their associated failure reasons.
      # Used for filtering repositories by failure reason in the UI.
      sig { returns(T::Hash[T.nilable(String), T::Array[T.nilable(String)]]) }
      memoize def token_map
        failures_map.group_by { |_, v| v["filter_token"] }.transform_values do |values|
          values.flatten!.select! { |v| v.is_a?(String) }
          T.cast(values, T::Array[T.nilable(String)])
        end
      end

      # Returns true if the enablement failures configuration is loaded.
      sig { returns(T::Boolean) }
      def loaded?
        failures_map.present?
      end

      private

      # Loads and caches the failures configuration from the JSON file.
      sig { returns(T::Hash[String, T.untyped]) }
      memoize def failures_map
        result = JSON.parse(File.read(ENABLEMENT_FAILURES_JSON_PATH))["failures"]
        T.cast(result, T::Hash[String, T.untyped])
      rescue JSON::ParserError, Errno::ENOENT => e
        Failbot.report(e)
        {}
      end
    end
  end
end
