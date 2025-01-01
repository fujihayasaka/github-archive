# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    class CancelSubscriptionItemFormComponent < ApplicationComponent
      extend T::Sig

      renders_one :heading
      renders_one :body
      renders_one :action_text

      sig { returns(Billing::Public::SubscriptionItem) }
      attr_reader :subscription_item

      sig { returns(String) }
      attr_reader :product_name

      sig { params(subscription_item: Billing::Public::SubscriptionItem, product_name: String).void }
      def initialize(subscription_item:, product_name:)
        @subscription_item = subscription_item
        @product_name = product_name
      end

      delegate :global_relay_id, :free_trial_length, :on_free_trial?, to: :subscription_item

      sig { returns(T.nilable(Survey)) }
      memoize def survey
        Survey.find_by(slug: ::Copilot::CfiCancellationSurvey::SURVEY_SLUG)
      end

      sig { returns(T::Boolean) }
      def render_survey?
        GitHub.flipper[:cfi_churn_survey].enabled? && survey.present?
      end
    end
  end
end
