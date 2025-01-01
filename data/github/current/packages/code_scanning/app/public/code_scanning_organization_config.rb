# typed: strict
# frozen_string_literal: true

class CodeScanningOrganizationConfig < T::Struct

  prop :organization, Orgs::IOrganization

  include Configurable
  include Configurable::CodeScanning
  include Configurable::CodeScanningAutofix

  # Configurables are currently stored associated with an organization
  sig { returns(String) }
  def configuration_entry_type
    "User"
  end

  sig { returns(::ActiveRecord::Relation) }
  def configuration_entries
    ::Configuration::Entry.where(target_id: organization.id, target_type: "User")
  end

  # This method is redeclared to avoid requiring `ApplicationRecord::Base` ancestry which the base implementation in Configurable does.
  sig { returns(Integer) }
  def configuration_entry_id
    T.must(organization.id)
  end

  # Internal: Get the configuration owner.
  #
  # Values for an Organization can be cascaded from (or overridden by)
  # a Business if the Organization is a member in a Business,
  # or the global GitHub object.
  sig { returns(T.nilable(Admin::IBusiness)) }
  def configuration_owner
    async_configuration_owner.sync
  end

  # Internal: Get the configuration owner asynchronously.
  #
  # Values for an Organization can be cascaded from (or overridden by)
  # a Business if the Organization is a member in a Business,
  # or the global GitHub object.
  sig { returns(Promise[T.nilable(Admin::IBusiness)]) }
  def async_configuration_owner
    organization.async_business.then { |business| business || GitHub }
  end
end
