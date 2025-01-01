# typed: strict
# frozen_string_literal: true

class AdvancedSecurity::LicenseAttributer
  extend T::Helpers

  include Licensing::Licensify
  include GitHub::Memoizer

  VALID_PRODUCTS = T.let([
    LicensifyProduct::GHAS,
    LicensifyProduct::CODE_SECURITY,
    LicensifyProduct::SECRET_PROTECTION,
  ], T::Array[LicensifyProduct])

  sig { returns(LicensifyProduct) }
  attr_reader :product

  sig { params(billable_entity: T.nilable(Billing::Types::OrgOrBusiness), product: LicensifyProduct).void }
  def initialize(billable_entity, product:)
    @billable_entity = billable_entity
    unless VALID_PRODUCTS.include?(product)
      raise ArgumentError, "Invalid product: #{product}. Must be one of #{VALID_PRODUCTS.map(&:serialize)}"
    end
    @product = product
  end

  sig { returns(T.nilable(Integer)) }
  memoize def customer_id
    return nil unless @billable_entity.present?
    ::Licensing::Customer.id_for(@billable_entity)
  end

  sig { returns(Integer) }
  memoize def active_cloud_user_count
    filter_grouped_counts(licensify_grouped_counts, active: true, server_only: false)
  end

  sig { returns(Integer) }
  memoize def billable_cloud_user_count
    filter_grouped_counts(licensify_grouped_counts, server_only: false)
  end

  sig { returns(Integer) }
  memoize def active_server_user_count
    filter_grouped_counts(licensify_grouped_counts, active: true, server_only: true)
  end

  sig { returns(Integer) }
  memoize def billable_server_user_count
    filter_grouped_counts(licensify_grouped_counts, server_only: true)
  end

  sig { returns(T::Array[Integer]) }
  memoize def active_user_ids
    licensify_licensee_ids.select { |id| id.to_s =~ /^\d+$/ }.map(&:to_i)
  end

  private

  sig { returns(T::Array[::Licensify::Services::V1::GroupedCount]) }
  memoize def licensify_grouped_counts
    return [] unless customer_id
    get_licensify_grouped_counts(T.must(customer_id), product:)
  end

  sig { returns(T::Array[String]) }
  memoize def licensify_licensee_ids
    return [] unless customer_id
    reasons = [
      Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_REPOSITORY_COMMITTER,
      Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ENTERPRISE_SERVER_USER,
    ]
    get_licensify_licensee_ids(T.must(customer_id), product:, enablement_reasons: reasons)
  end

  sig { returns(T::Hash[String, String]) }
  def licensify_error_tags
    {
      "gh.customer.id": customer_id,
      "gh.billable_entity.id": @billable_entity&.id,
      "gh.billable_entity.type": @billable_entity&.class&.name,
      "licensify.product": product.to_s,
    }
  end
end
