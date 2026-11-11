# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Quota
      class UsageComponent < ApplicationComponent

        sig { returns(Integer) }
        attr_reader :completions_percentage_used

        sig { returns(Integer) }
        attr_reader :chat_percentage_used

        sig { returns(T::Boolean) }
        attr_reader :any_quotas_exhausted

        sig { returns(T::Boolean) }
        attr_reader :has_error

        sig do
          params(
            completions_percentage_used: Integer,
            chat_percentage_used: Integer,
            any_quotas_exhausted: T::Boolean,
            has_error: T::Boolean
          ).void
        end
        def initialize(
            completions_percentage_used:,
            chat_percentage_used:,
            any_quotas_exhausted: false,
            has_error: false
          )
          @completions_percentage_used = completions_percentage_used
          @chat_percentage_used = chat_percentage_used
          @any_quotas_exhausted = any_quotas_exhausted
          @has_error = has_error
        end
      end
    end
  end
end
