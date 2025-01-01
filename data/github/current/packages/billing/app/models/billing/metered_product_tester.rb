# typed: true
# frozen_string_literal: true

module Billing
  class MeteredProductTester
    include GitHub::Memoizer
    attr_reader :usage_quote, :usage_breakdown, :error_message

    def initialize(product_name:, product_sku_name:, quantity:, source:, user:)
      @product_name = product_name
      @product_sku_name = product_sku_name
      @quantity = quantity.presence.try(:to_f)
      @source = source
      @user = user
      @usage_emitted = false
      @usage_breakdown = nil
      @error_message = nil
    end

    def emit_test_usage
      return unless all_required_params_present?

      source_info = if source_object.customer
        {
          account_id: nil,
          customer_id: source_object.customer.id,
        }
      else
        {
          account_id: source_object.id,
          customer_id: nil
        }
      end

      GlobalInstrumenter.instrument("meuse.metered_usage", {
        product_name: @product_name,
        product_sku_name: @product_sku_name,
        actor_id: @user.id,
        quantity: @quantity,
        usage_at: Time.now,
        usage_uuid: SecureRandom.uuid,
        source_uri: "gid://stafftools_test",
        custom_fields: {},
      }.merge(source_info))

      @usage_emitted = true
    end

    def calculate_test_usage
      return nil unless all_required_params_present?

      usage_checker = Billing::UsageChecker.new(account: source_object, product_names: [@product_name])
      usage_breakdown = usage_checker.usage_for(product: @product_name, sku: @product_sku_name, include_budget: false)
      if usage_checker.request_error?
        @error_message = "Error getting usage breakdown."
        nil
      else
        usage_breakdown
      end
    end

    def usage_emitted?
      @usage_emitted
    end

    private

    def all_required_params_present?
      @product_name.present? && @product_sku_name.present? && @quantity.present? && @source.present?
    end

    memoize def source_object
      u, o, e = %w(User Org Enterprise)

      case @source.split("_")
      in ^u, _
        @user
      in ^o, id
        T.must(Organization.find(id))
      in ^e, id
        T.must(Business.find(id))
      else
        raise "Unable to parse the source: #{@source}"
      end
    end
  end
end
