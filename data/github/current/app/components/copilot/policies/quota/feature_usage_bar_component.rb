# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Quota
      class FeatureUsageBarComponent < ApplicationComponent

        sig { returns(String) }
        attr_reader :feature_name

        sig { returns(String) }
        attr_reader :feature_key

        sig { returns(Integer) }
        attr_reader :percentage_used

        sig { returns(T::Boolean) }
        attr_reader :any_quotas_exhausted

        sig { returns(T::Boolean) }
        attr_reader :has_error

        sig do
          params(
            feature_name: String,
            feature_key: String,
            percentage_used: Integer,
            any_quotas_exhausted: T::Boolean,
            has_error: T::Boolean
          ).void
        end
        def initialize(
            feature_name:,
            feature_key:,
            percentage_used:,
            any_quotas_exhausted:,
            has_error: false
          )
          @feature_name = feature_name
          @feature_key = feature_key
          @percentage_used = percentage_used
          @any_quotas_exhausted = any_quotas_exhausted
          @has_error = has_error
        end

        sig { returns(String) }
        def percentage_used_text
          has_error ? "--" : "#{percentage_used}%"
        end

        sig { returns(Integer) }
        def percentage
          has_error ? 0 : percentage_used
        end

        sig { returns(Symbol) }
        def progress_bar_color
          any_quotas_exhausted ? :attention_emphasis : :success_emphasis
        end

        sig { returns(String) }
        def aria_label
          "Copilot #{feature_name.downcase} quota usage"
        end
      end
    end
  end
end
