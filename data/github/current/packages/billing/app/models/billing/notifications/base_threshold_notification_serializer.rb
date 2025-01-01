# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class BaseThresholdNotificationSerializer
      extend T::Helpers
      abstract!

      include UrlHelpers
      include ActionView::Helpers::NumberHelper
      include ActionView::Helpers::UrlHelper
      include GitHub::Memoizer

      attr_reader :notification

      delegate :owner, :billable_owner, :context, :actor, :result, to: :notification

      class ProductEnum < T::Enum
        enums do
          Actions = new
          Codespaces = new
          Copilot = new
          Ghas = new
          Ghec = new
          Git_Lfs = new
          Packages = new
        end
      end

      sig { params(notification: T.untyped).void }
      def initialize(notification)
        @notification = notification
      end

      sig { returns(String) }
      def text
        if resource.target.is_a?(::Repository)
          usage_text_for_target("repo")
        elsif resource.target.is_a?(::Organization)
          usage_text_for_target("org")
        elsif resource.target.is_a?(Billing::Platform::Api::CostCenter)
          usage_text_for_target("cost center")
        elsif owner.is_a?(::Organization) || context.is_a?(::Repository)
          "Your enterprise has used #{result.threshold}% of its #{resource_type} for #{metered_service_name}."
        elsif resource.target.is_a?(User)
          "You've used #{result.threshold}% of your #{metered_service_name} #{resource_type}."
        else
          "You've used #{result.threshold}% of the #{metered_service_name} #{resource_type} for your Enterprise."
        end
      end

      sig { params(target_type: String).returns(String) }
      def usage_text_for_target(target_type)
        "You've used #{result.threshold}% of your #{metered_service_name} #{resource_type} for the #{resource.target_name} #{target_type}."
      end

      sig { returns(String) }
      def usage_reset_date_text
        "Your usage will reset on #{owner.billable_owner.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}"
      end

      sig { returns(String) }
      def metered_service_name
        case resource.pricing_target_id
        when ProductEnum::Actions.serialize
          "Actions"
        when ProductEnum::Codespaces.serialize
          "Codespaces"
        when ProductEnum::Copilot.serialize
          "Copilot"
        when ProductEnum::Ghas.serialize
          "GitHub Advanced Security"
        when ProductEnum::Ghec.serialize
          "GitHub Enterprise Cloud"
        when ProductEnum::Git_Lfs.serialize
          "Git LFS"
        when ProductEnum::Packages.serialize
          "Packages"
        else
          begin
            pricing = billing_platform_client.get_pricing(sku: resource.pricing_target_id)
            if pricing.is_a?(Hash) && pricing.dig(:pricing, :friendlyName).present?
              pricing[:pricing][:friendlyName]
            else
              "metered services"
            end
          rescue => e
            Rails.logger.error("Error fetching pricing: #{e.message}")

            "metered services"
          end
        end
      end

      sig { returns(Integer) }
      def threshold
        result.threshold
      end

      sig { returns(String) }
      def mail_icon
        "cogs.png"
      end

      sig { returns(String) }
      def progress_bar_details_text
        context = result.context

        is_license_budget = context[:is_license_budget]

        billable_owner = owner&.billable_owner
        if is_license_budget && FeatureFlag.vexi.enabled?(:billing_hard_budget_limits_for_licenses, billable_owner, default: false)
          used = context[:budget_state_quantity].to_i.to_s
          available = context[:available].to_i.to_s

          "#{used} of #{available} licenses"
        else
          used = number_to_currency(context[:used])
          available = number_to_currency(context[:available])

          "#{used} of #{available}"
        end

      end

      sig { returns(String) }
      def slack_notification_message
        "used #{result.value}% of paid usage services"
      end

      sig { returns(T::Array[String]) }
      def filtered_by_tags
        result.tags
      end

      sig { returns(T::Array[String]) }
      def product_tags
        [resource.product_name]
      end

      sig { returns(T.nilable(Float)) }
      def meter_available
        context = result.context
        return unless context.present?

        result.context[:available]
      end

      sig { returns(T::Boolean) }
      def is_actor_enterprise_owner?
        return false unless actor.present?

        business = owner.billable_owner
        business.owners.include?(actor)
      end

      # To be overridden by subclasses
      sig { abstract.returns(T.untyped) }
      def resource; end

      sig { abstract.returns(String) }
      def resource_type; end

      sig { abstract.returns(String) }
      def mail_subject; end

      sig { abstract.returns(String) }
      def mail_product_title; end

      sig { abstract.returns(String) }
      def progress_bar_title; end

      sig { abstract.returns(Symbol) }
      def variant; end

      private

      sig { returns(::Billing::Platform::Api::Client) }
      memoize def billing_platform_client
        ::Billing::Platform::Api::Client.new
      end
    end
  end
end
