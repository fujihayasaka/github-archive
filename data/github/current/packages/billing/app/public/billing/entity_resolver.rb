# typed: strict
# frozen_string_literal: true

module Billing
  # Utility class for resolving billing-related entities and customer information.
  # This class provides methods to determine billing ownership and customer IDs
  # for repositories, organizations, and businesses.
  class EntityResolver
    # Returns the billing owner entity for the given entity.
    # For repositories: returns the business if owner delegates billing, otherwise returns the owner.
    # For organizations: returns the business if billing is delegated, otherwise returns the organization.
    # For businesses: returns the business itself.
    sig { params(entity: T.any(Repository, Business, Organization)).returns(T.any(User, Business, Organization)) }
    def self.billing_owner(entity)
      if entity.is_a?(Repository)
        if entity.owner&.delegate_billing_to_business?
          return entity.owner&.business
        else
          return T.must(entity.owner)
        end
      elsif entity.is_a?(Organization)
        if entity.delegate_billing_to_business?
          return T.must(entity.business)
        end
      end
      # Non-delegating org, or enterprise
      entity
    end

    # Returns the customer ID for the billing owner of the entity.
    # Returns nil if the billing owner does not have a customer.
    sig { params(entity: T.any(Repository, Organization, Business)).returns(T.nilable(Integer)) }
    def self.customer_id(entity)
      billing_owner = billing_owner(entity)
      if billing_owner.is_a?(Business)
        return billing_owner.customer_id
      end
      billing_owner.customer&.id
    end
  end
end
