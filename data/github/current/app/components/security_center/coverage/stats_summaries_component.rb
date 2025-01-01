# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    class StatsSummariesComponent < ApplicationComponent
      extend T::Sig

      class AsyncData < T::Struct
        const :src, String
      end

      class Data < T::Struct
        extend T::Sig

        const :summaries, T::Array[StatsSummaryComponent::Data]
      end

      TEST_SELECTOR = "security-center-coverage-stats-summaries"
      SPINNER_TEST_SELECTOR = "security-center-coverage-stats-summaries-spinner"

      sig { params(data: T.any(AsyncData, Data), system_args: T.untyped).void }
      def initialize(data, **system_args)
        @system_args = system_args

        if data.is_a?(AsyncData)
          @src = T.let(data.src, T.nilable(String))
        elsif data.is_a?(Data)
          @summaries = T.let(data.summaries, T.nilable(T::Array[StatsSummaryComponent::Data]))
        end
      end
    end
  end
end
