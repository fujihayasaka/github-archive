# typed: strict
# frozen_string_literal: true

module TradeControls
  class TradeScreeningRecordLink
    extend T::Sig

    sig { returns(Organization) }
    attr_reader :organization

    sig { params(organization: Organization).void }
    def initialize(organization:)
      @organization = organization
    end

    # Public: The ID of the trade screening record that was linked.
    sig { returns(T.nilable(Integer)) }
    def link_id
      id = TradeCompliance::Kv.store.get(link_key).value { nil }
      id.to_i if id
    end

    # Public: Update the trade screening record link for an organization.
    sig { params(id: Integer).returns(TrueClass) }
    def update(id:)
      existing_link_id = link_id
      link_id_changed = id != existing_link_id

      if link_id_changed
        set_link!(id)
      end

      true
    end

    # Public: Remove the trade screening record link for the organization.
    sig { void }
    def remove
      existing_link_id = link_id
      TradeCompliance::Kv.store.del(link_key)
    end

    private

    sig { returns(String) }
    def link_key
      "organization.#{organization.id}.trade_screening_ref"
    end

    # Private: Set the stored trade screening record link value for this organization.
    sig { params(value: Integer).void }
    def set_link!(value)
      TradeCompliance::Kv.store.set(link_key, value.to_s)
    end
  end
end
