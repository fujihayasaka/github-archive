# typed: strict
# frozen_string_literal: true

module Asset::Status::ZuoraDependency
  extend ActiveSupport::Concern

  ZUORA_PRODUCT_TYPE = "github.lfs"

  class_methods do
    extend T::Sig
    extend T::Helpers

    requires_ancestor { T.class_of(::Asset::Status) }

    sig { params(cycle: String).returns(String) }
    def zuora_id(cycle:)
      T.must(product_uuid(cycle)).zuora_product_rate_plan_id
    end

    sig { params(cycle: String).returns(T::Hash[T.any(String, Symbol), String]) }
    def zuora_charge_ids(cycle:)
      T.must(product_uuid(cycle)).zuora_product_rate_plan_charge_ids
    end

    sig { params(billing_cycle: String).returns(T.nilable(Billing::ProductUUID)) }
    def product_uuid(billing_cycle)
      ::Billing::ProductUUID.find_by(product_type: ZUORA_PRODUCT_TYPE, product_key: "v0", billing_cycle: billing_cycle)
    end

    sig { void }
    def sync_to_zuora
      GitHub::Billing::ZuoraProduct.create \
        product_type: ZUORA_PRODUCT_TYPE,
        product_key: "v0",
        product_name: zuora_product_name,
        charges: zuora_charges
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def zuora_charges
      [{
        type: :unit,
        prices: { year: yearly_cost_in_dollars, month: monthly_cost_in_dollars },
        unit: "Seats",
      }]
    end

    sig { returns(BigDecimal) }
    def yearly_cost_in_dollars
      Billing::Money.new(data_pack_unit_price * 12).dollars
    end

    sig { returns(BigDecimal) }
    def monthly_cost_in_dollars
      data_pack_unit_price.dollars
    end

    sig { returns(String) }
    def zuora_product_name
      "Git LFS Data Pack"
    end
  end
end
