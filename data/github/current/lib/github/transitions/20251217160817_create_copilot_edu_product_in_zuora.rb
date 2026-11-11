# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class CreateCopilotEduProductInZuora < Base
      include ::Billing::ZuoraProduct::ZuoraSettings

      PRODUCT_NAME = "GitHub Copilot Edu"
      PRODUCT_TYPE = "github.copilot"
      PRODUCT_KEY  = "edu"

      MONTHLY_UNIT_PRICE_IN_USD = 0

      sig { override.void }
      def perform
        return unless GitHub.billing_enabled?
        log "Syncing - #{PRODUCT_NAME}"
        GitHub.zuorest_client.timeout = 60

        if existing_product_uuid?
          log "Monthly ProductUUID found for `#{PRODUCT_NAME}`"
        elsif !dry_run?
          create_product
        end
      end

      private

      sig { void }
      def create_product
        ::Billing::ZuoraProduct.create(
          product_type: PRODUCT_TYPE,
          product_key: PRODUCT_KEY,
          product_name: PRODUCT_NAME,
          charges: [{
            type: :flat,
            prices: {
              ::User::BillingDependency::MONTHLY_PLAN.to_sym => MONTHLY_UNIT_PRICE_IN_USD
            },
          }],
          billing_frequencies: [::User::BillingDependency::MONTHLY_PLAN]
        )
      rescue Zuorest::HttpError => e
        log "Error when attempting to sync #{PRODUCT_NAME} to Zuora, see details:"
        log e.inspect
        log e.data
      ensure
        msg  = existing_product_uuid? ? "was successful" : "failed"
        log "Sync for `#{PRODUCT_NAME}` #{msg}"
      end

      sig { returns(T::Boolean) }
      def existing_product_uuid?
        scope = ::Billing::ProductUUID.where(product_type: PRODUCT_TYPE, product_key: PRODUCT_KEY)
        scope.where(billing_cycle: ::User::BillingDependency::MONTHLY_PLAN).exists?
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::CreateCopilotEduProductInZuora.new(args).run
end
