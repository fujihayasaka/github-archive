# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Businesses
    class AddAzureSubscription < Base
      sig { override.returns(String) }
      def title
        "Add Azure subscription"
      end

      sig { override.returns(String) }
      def task_link
        settings_billing_tab_enterprise_path(business, :payment_information)
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        business.linked_azure_subscription?
      end

      sig { override.returns(T.nilable(String)) }
      def icon_path
        nil
      end
    end
  end
end
