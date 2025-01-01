# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module MachinePolicy
    extend T::Sig
    extend PolicyFilter

    def self.machine_type_allowed?(sku_name:, billable_owner:, repository:)
      value_allowed?(
        value_name: sku_name,
        billable_owner: billable_owner,
        repository: repository,
      )
    end

    # Returns skus filtered by the machine policy associated with the repository organization
    # If there is no policy or constraints, the skus are returned unmodified
    def self.filter_skus_by_machine_policy(skus:, repository:, billable_owner:)
      return [] if skus.empty?

      allowlists = get_allowlists(billable_owner: billable_owner, repository: repository)

      return skus if allowlists.empty?

      # Get intersection of allowed SKUs, note that if any are the empty set, none will be allowed.
      allowed_skus = allowlists.reduce(:&)

      return [] if allowed_skus.empty?

      skus.select { |sku| sku.name.to_s.in?(allowed_skus) }
    end

    sig { override.returns(String) }
    def self.policy_name
      Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES
    end
  end
end
