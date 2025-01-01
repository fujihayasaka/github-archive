# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    class Processor
      sig { params(user: User, form_values: T::Hash[Symbol, String]).returns(Result) }
      def self.call(user:, form_values:)
        new(user:, form_values:).call
      end

      sig { params(user: User, form_values: T::Hash[Symbol, String]).void }
      def initialize(user:, form_values:)
        @user = user
        @form_values = form_values
      end

      sig { returns(Result) }
      def call
        subject = EducationDeveloperPackApplicationMetadata.create(
          user:,
          application_type:,
          applied_at:,
        )

        Result.new(subject:)
      end

      private

      sig { returns(User) }
      attr_reader :user

      sig { returns(T::Hash[Symbol, String]) }
      attr_reader :form_values

      sig { returns(Symbol) }
      def application_type
        T.must(form_values[:application_type]).to_sym
      end

      sig { returns(DateTime) }
      def applied_at
        DateTime.now
      end
    end
  end
end
