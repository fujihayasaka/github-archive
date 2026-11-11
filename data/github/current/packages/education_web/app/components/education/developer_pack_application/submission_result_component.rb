# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    class SubmissionResultComponent < ApplicationComponent
      SUCCESS_MESSAGE = T.let("Your application has been submitted.".freeze, String)

      sig { params(result: DeveloperPackApplication::Result).void }
      def initialize(result:)
        @result = result
      end

      sig { returns(String) }
      def call
        render(Primer::Alpha::Banner.new(scheme:).with_content(message))
      end

      private

      sig { returns(DeveloperPackApplication::Result) }
      attr_reader :result

      sig { returns(Symbol) }
      def scheme
        if result.success?
          :success
        else
          :danger
        end
      end

      sig { returns(T.nilable(String)) }
      def message
        if result.success?
          SUCCESS_MESSAGE
        else
          result.error.message
        end
      end
    end
  end
end
