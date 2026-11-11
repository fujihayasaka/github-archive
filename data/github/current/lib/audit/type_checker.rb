# typed: true
# frozen_string_literal: true

module Audit
  class TypeChecker

    KEYS_TO_CHECK = {
      owner_id: Integer,
      actor_id: Integer,
      org_id: Integer,
      user_id: Integer,
      business_id: Integer,
    }

    def self.check_payload(payload = {})
      payload = payload.symbolize_keys
      mark_invalid = T.let(false, T::Boolean)
      payload.compact.each do |key, value|
        if KEYS_TO_CHECK.key?(key)
          if check_type(key, value)
            mark_invalid = true
          end
        end
      end

      if mark_invalid
        payload[:data] ||= {}
        payload[:data][:_invalid] = true
      end
      payload
    end

    private

    def self.check_type(key, value)
      return false if GitHub.single_business_environment?
      return false if value.is_a?(KEYS_TO_CHECK[key])
      return false if value.is_a?(Array) && value.all? { |v| v.is_a?(KEYS_TO_CHECK[key]) }

      GitHub.dogstats.increment("audit.type_checker.fail", tags: ["type:#{value.class}", "action:#{key}"])

      err = TypeError.new("Expected #{key} to be an integer, but was #{value.class}")

      Failbot.report(err, { action: key })

      raise err if GitHub.audit_log_raise_on_verify?

      true
    end
    private_class_method :check_type
  end
end
