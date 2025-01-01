# typed: strict
# frozen_string_literal: true

module Billing
  class ContactLink

    sig { returns(Organization) }
    attr_reader :organization
    sig { returns(Symbol) }
    attr_reader :contact_type

    sig { params(organization: Organization, contact_type: Symbol).void }
    def initialize(organization:, contact_type:)
      @organization = organization
      @contact_type = contact_type
    end

    # Public: The ID of the billing contact that was linked.
    sig { returns(T.nilable(Integer)) }
    def link_id
      id = Billing::Kv.store.get(link_key).value { nil }
      id.to_i if id
    end

    # Public: Update the billing contact link for an organization.
    sig { params(id: Integer).returns(TrueClass) }
    def update(id:)
      existing_link_id = link_id
      link_id_changed = id != existing_link_id

      if link_id_changed
        set_link!(id)
      end

      true
    end

    # Public: Remove the billing contact link for the organization.
    sig { void }
    def remove
      Billing::Kv.store.del(link_key)
    end

    private

    sig { returns(String) }
    def link_key
      "organization.#{organization.id}.#{contact_type}_contact_ref"
    end

    # Private: Set the stored billing contact link value for this organization.
    sig { params(value: Integer).void }
    def set_link!(value)
      Billing::Kv.store.set(link_key, value.to_s)
    end
  end
end
