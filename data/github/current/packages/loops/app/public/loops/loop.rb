# typed: strict
# frozen_string_literal: true

module Loops
  # Plain old Ruby object representing a Loop domain entity returned by the
  # Loops service. This object is intentionally lightweight and only exposes
  # the small set of attributes currently consumed in the monolith.
  #
  # It includes GlobalIdentification so callers can access `global_relay_id`.
  # Since Loops entities are new to GraphQL, they always use the "next" global
  # ID format defined by the GraphQL object type `Platform::Objects::Loops::Loop`.
  class Loop
    include GitHub::Relay::GlobalIdentification

    sig { returns(String) }
    attr_reader :uuid

    sig { returns(T.nilable(Integer)) }
    attr_reader :owner_id

    sig { returns(T.nilable(String)) }
    attr_reader :owner_login

    sig { returns(T.nilable(String)) }
    attr_reader :title

    sig { returns(T.nilable(String)) }
    attr_reader :description

    sig { returns(T.nilable(String)) }
    attr_reader :version

    sig { returns(T.nilable(Time)) }
    attr_reader :updated_at

    sig { returns(T.nilable(String)) }
    attr_reader :visibility

    sig { returns(T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])) }
    attr_reader :nodes

    # Public: Initialize a new Loop instance.
    #
    # uuid - The String UUID of the Loop.
    # owner_login - The login of the User who owns the Loop.
    # name - The String name of the Loop.
    # description - The String description of the Loop.
    # share_id - The optional String share ID of the Loop.
    # version - The optional String version of the Loop.
    # updated_at - The optional Time the Loop was last updated.
    # visibility - The optional String visibility of the Loop ("public" or "private").
    # nodes - The optional Array of Hash nodes that make up the Loop definition.
    sig { params(uuid: String, owner_id: T.nilable(Integer), owner_login: T.nilable(String), title: T.nilable(String), description: T.nilable(String), share_id: T.nilable(String), version: T.nilable(String), updated_at: T.nilable(Time), visibility: T.nilable(String), nodes: T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])).void }
    def initialize(uuid:, owner_id:, owner_login:, title:, description:, share_id: nil, version: nil, updated_at: nil, visibility: nil, nodes: nil)
      @uuid = uuid
      @owner_id = owner_id
      @owner_login = owner_login
      @title = title
      @description = description
      @share_id = share_id
      @version = version
      @updated_at = updated_at
      @visibility = visibility
      @nodes = nodes
    end

    # Public: The global relay ID for this Loop.
    #
    # Returns a String.
    sig { returns(String) }
    def id
      uuid
    end

    # Public: Whether this Loop is shared (i.e., has a share ID).
    #
    # Returns a Boolean.
    sig { returns(T::Boolean) }
    def shared?
      visibility == "public"
    end
  end
end
