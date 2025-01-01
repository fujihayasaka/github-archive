# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Businesses
    class Base < OnboardingTasks::AbstractTask
      extend T::Helpers

      abstract!

      sig { returns(Business) }
      attr_reader :business

      sig { params(user: T.nilable(User), taskable: Business, attributes: T::Hash[String, T.untyped]).void }
      def initialize(user:, taskable:, attributes: {})
        super
        @business = T.let(taskable, Business)
      end
    end
  end
end
