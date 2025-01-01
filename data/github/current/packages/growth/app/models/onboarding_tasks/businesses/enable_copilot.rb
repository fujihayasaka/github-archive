# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Businesses
    class EnableCopilot < Base
      include GitHub::Memoizer

      sig { override.returns(String) }
      def title
        "Enable access to #{Copilot.business_product_name}"
      end

      sig { override.returns(String) }
      def task_link
        enterprise_licensing_path(business)
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        !copilot_team.nil?
      end

      sig { returns(T::Boolean) }
      def completed?
        super && verify_task
      end

      sig { override.returns(T.nilable(String)) }
      def icon_path
        nil
      end

      private

      sig { returns(T.nilable(EnterpriseTeam)) }
      memoize def copilot_team
        EnterpriseTeam.get_copilot_team(business)
      end
    end
  end
end
