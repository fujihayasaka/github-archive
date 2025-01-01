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

        sig { params(subscription_item: Billing::Public::SubscriptionItem, product_name: String, dialog_id: String).void }
        def initialize(subscription_item:, product_name:, dialog_id:)
          @subscription_item = subscription_item
          @product_name = product_name
          @dialog_id = dialog_id
        end

        sig { returns(String) }
        def next_billing_date
          subscription_item.next_billing_date.strftime("%b %d, %Y".freeze)
        end

      end
    end
  end
end
