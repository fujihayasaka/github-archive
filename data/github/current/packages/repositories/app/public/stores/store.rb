# typed: true # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

module Stores
  class Store
    include GitHub::VexiActor
    include SpokesAPI::ContextDependency
    include ::Store::DGit
    include ::Store::SpokesAPI

    delegate :id, :spokes_id, :created_at, :deleted_at, :owner_id, :state, to: :@attributes

    sig do
      params(
        id: String,
        spokes_id: Integer,
        created_at: Time,
        deleted_at: T.nilable(Time),
        owner_id: Integer,
        state: Integer,
      ).void
    end
    def initialize(id, spokes_id, created_at, deleted_at, owner_id, state)
      @attributes = T.let(StoreAttributes.new(id, spokes_id, created_at, deleted_at, owner_id, state), StoreAttributes)
    end

    sig { override.returns(String) }
    def feature_flag_actor_name
      "Stores::Store#{VEXI_ID_SEPARATOR}#{id}"
    end

    STATE_MAPPING = T.let({
      "STORE_STATE_CREATING" => 0,
      "STORE_STATE_ACTIVE" => 1,
      "STORE_STATE_DELETED" => 2,
    }.freeze, T::Hash[String, Integer])

    sig { params(data: T::Hash[String, T.untyped]).returns(Store) }
    def self.from_reposd(data)
      new(
        data["id"],
        data["spokes_id"].to_i,
        Time.parse(data["created_at"]),
        data["deleted_at"] ? Time.parse(data["deleted_at"]) : nil,
        data["owner_id"].to_i,
        STATE_MAPPING.fetch(data["state"].to_s, 0),
      )
    end
  end
end
