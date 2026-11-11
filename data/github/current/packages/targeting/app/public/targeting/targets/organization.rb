# typed: strict
# frozen_string_literal: true

module Targeting
  # Helper to create a targetable object for an Organization
  # Long-term, it may make sense to have Organization implement Targetable directly if we choose to use
  # Targetable as a universal interface for all targetable objects
  class Targets::Organization
    include Targetable

    sig { params(organization: Organization).void }
    def initialize(organization:)
      @organization = organization
    end

    sig { override.returns(Organization) }
    def internal_record
      @organization
    end

    sig { override.returns(T::Hash[Targeting::Attribute, T.untyped]) }
    def targetable_attributes
      {
        Attribute::Organization => @organization,
        Attribute::OrganizationCustomProperties => -> do
          Orgs.domain.custom_properties.effective_values_for_org(@organization)
        end,
        Attribute::OrganizationName => @organization.name,
      }
    end

    sig { override.returns(Promise[T::Array[Targeting::Targetable]]) }
    def async_targetable_parents
      @organization.async_business.then do |business|
        next [] if business.nil?
        [Targets::Enterprise.new(business: business)]
      end
    end
  end
end
