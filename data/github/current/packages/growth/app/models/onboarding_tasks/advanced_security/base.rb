# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module AdvancedSecurity
    class Base < OnboardingTasks::AbstractTask
      extend T::Helpers

      abstract!

      sig { returns(Organization) }
      attr_reader :organization

      sig { params(user: T.nilable(User), taskable: Organization).void }
      def initialize(user:, taskable:)
        super
        @organization = T.let(taskable, Organization)
      end

      sig { override.returns(T.nilable(String)) }
      def icon_path
        nil
      end

      sig { override.returns(Symbol) }
      def octicon
        :"shield-check"
      end
    end
  end
end
