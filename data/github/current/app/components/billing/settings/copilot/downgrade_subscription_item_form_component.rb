# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Copilot
      class DowngradeSubscriptionItemFormComponent < ApplicationComponent
        renders_one :heading
        renders_one :body
        renders_one :action_text

        sig { returns(Billing::Public::SubscriptionItem) }
        attr_reader :subscription_item

        sig { returns(String) }
        attr_reader :product_name

        sig { returns(String) }
        attr_reader :dialog_id

        sig { returns(String) }
        attr_reader :downgrade_path

        sig { returns(String) }
        attr_reader :downgraded_product_name

        sig { params(subscription_item: Billing::Public::SubscriptionItem, product_name: String, dialog_id: String, downgrade_path: String, downgraded_product_name: String).void }
        def initialize(subscription_item:, product_name:, dialog_id:, downgrade_path:, downgraded_product_name:)
          @subscription_item = subscription_item
          @product_name = product_name
          @dialog_id = dialog_id
          @downgrade_path = downgrade_path
          @downgraded_product_name = downgraded_product_name
        end

        sig { returns(String) }
        def next_billing_date
          subscription_item.next_billing_date.strftime("%b %d, %Y".freeze)
        end
      end
    end
  end
end
