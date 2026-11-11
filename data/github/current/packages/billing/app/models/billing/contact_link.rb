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
      @link_value ||= T.let(nil, T.nilable(Integer))
    end

    # Public: The ID of the billing contact that was linked.
    sig { returns(T.nilable(Integer)) }
    def link_id
      @link_value ||= Billing::Kv.store.get(link_key).value { nil }
      @link_value.to_i if @link_value
    end

    # Public: Update the billing contact link for an organization.
    sig { params(id: Integer).returns(TrueClass) }
    def update(id:)
      set_link!(id) if id != link_id

      true
    end

    # Public: Remove the billing contact link for the organization.
    sig { void }
    def remove
      Billing::Kv.store.del(link_key)
      @link_value = nil
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
      @link_value = value
    end
  end
end
