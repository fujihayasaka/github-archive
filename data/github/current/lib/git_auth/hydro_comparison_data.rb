# typed: true
# frozen_string_literal: true

module GitAuth
  class HydroComparisonData
    FEATURE_FLAG_CONTEXT_KEY = :gitauth_include_hydro_comparison_data
    ADDITIONAL_DATA_CONTEXT_KEY = :gitauth_gotauth_hydro_comparison_data
    AUTHND_RESULT_CONTEXT_KEY = :gitauth_authnd_result
    AUTHZD_RESULTS_CONTEXT_KEY = :gitauth_authzd_results

    sig { returns(T::Hash[String, T.untyped]) }
    def self.get_data
      return {} unless self.enabled?

      self.get_or_set_context_value(ADDITIONAL_DATA_CONTEXT_KEY, {})
    end

    sig { params(key: String).returns(T.untyped) }
    def self.get_data_item(key)
      return nil unless self.enabled?

      self.get_data[key]
    end

    sig { params(key: String, value: T.untyped).void }
    def self.set_data_item(key, value)
      return unless self.enabled?

      self.get_data[key] = value
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def self.get_authnd_result
      return {} unless self.enabled?

      self.get_or_set_context_value(AUTHND_RESULT_CONTEXT_KEY, {})
    end

    sig { params(result: { success: T::Boolean, failure_type: T.untyped, failure_reason: T.untyped }).void }
    def self.set_authnd_result(result)
      return unless self.enabled?

      self.set_context_value(AUTHND_RESULT_CONTEXT_KEY, result)
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.get_authzd_results
      return [] unless self.enabled?

      self.get_or_set_context_value(AUTHZD_RESULTS_CONTEXT_KEY, [])
    end

    sig { params(cache_key: T.untyped, response: T.nilable(Authzd::Response)).void }
    def self.add_authzd_result(cache_key, response)
      return unless self.enabled?

      result = if response.present? && response.error?
        { error: response.error }
      elsif response.present? && response.decision.present?
        response.decision.to_h.slice(:result, :reason)
      else
        { result: "UNKNOWN" }
      end

      result[:attrs] = cache_key.second if cache_key.is_a?(Array) && cache_key.second.is_a?(Hash)

      results = self.get_authzd_results
      results << result
    end

    def self.enabled?
      return false unless GitHub.role == :gitauth || !!ENV["GITAUTH"]

      self.get_or_set_context_value(FEATURE_FLAG_CONTEXT_KEY) do
        FeatureFlag.vexi.enabled?(:gitauth_include_hydro_comparison_data, default: false)
      end
    end
    private_class_method :enabled?

    sig { params(key: Symbol, default_value: T.untyped, default_value_block: T.nilable(Proc)).returns(T.untyped) }
    def self.get_or_set_context_value(key, default_value = nil, &default_value_block)
      if GitHub.context[key].nil?
        if default_value.nil? && block_given?
          default_value = default_value_block.call
        end

        self.set_context_value(key, default_value)
      end

      GitHub.context[key]
    end
    private_class_method :get_or_set_context_value

    sig { params(key: Symbol, value: T.untyped).void }
    def self.set_context_value(key, value)
      GitHub.context.push(**{ key => value })
    end
    private_class_method :set_context_value
  end
end
