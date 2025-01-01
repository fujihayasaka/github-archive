# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    class Result
      ErrorTypes = T.type_alias do
        T.any(
          Errors::None,
          Errors::UserNotEligible,
        )
      end

      sig { params(subject: EducationDeveloperPackApplicationMetadata).void }
      def initialize(subject:)
        @subject = subject
      end

      sig { returns(T::Boolean) }
      def success?
        @subject.persisted?
      end

      sig { returns(ErrorTypes) }
      def error
        if @subject.errors.any?
          Errors::UserNotEligible.new
        else
          Errors::None.new
        end
      end
    end
  end
end
