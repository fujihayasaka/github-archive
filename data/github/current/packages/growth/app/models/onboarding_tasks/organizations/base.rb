# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Organizations
    class Base < OnboardingTasks::AbstractTask
      extend T::Helpers

      abstract!

      sig { returns(Organization) }
      attr_reader :organization

      sig { params(user: T.nilable(User), taskable: Organization, attributes: T::Hash[String, T.untyped]).void }
      def initialize(user:, taskable:, attributes: {})
        super
        @organization = T.let(taskable, Organization)
      end

      sig { returns(T::Array[Integer]) }
      def repo_ids
        @repo_ids ||= T.let(organization.repositories.pluck(:id), T.nilable(T::Array[Integer]))
      end

      sig { returns(T.nilable(Repository)) }
      def demo_repo
        return @demo_repo if defined?(@demo_repo)

        @demo_repo = T.let(::OrganizationOnboard::DemoRepository.repository_for(organization), T.nilable(Repository))
      end

      sig { returns(T::Boolean) }
      def enabled_for_plan?
        return false if GitHub.enterprise?
        case organization.plan
        when GitHub::Plan.business
          Onboard::TEAM_TASKS.include?(self.class)
        when GitHub::Plan.business_plus
          Onboard::GHEC_TASKS.include?(self.class)
        else
          Onboard::FREE_TASKS.include?(self.class)
        end
      end

      sig { returns(T::Boolean) }
      def require_demo_repository?
        false
      end
    end
  end
end
