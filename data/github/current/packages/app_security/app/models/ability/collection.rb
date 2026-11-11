# typed: true
# frozen_string_literal: true

# Public: An entity that allows an abstract collection to be treated
# as an Ability subject.
# Common collections are grouped sub-resources of a Repository, for example
# metadata, administration, contents, and issues.

class Ability
  class Collection
    include Ability::Subject
    include Ability::Membership

    def initialize(parent:, name:, ability_type_prefix: nil)
      @parent = parent
      @name = name
      @ability_type_prefix = ability_type_prefix || parent.class.name
    end

    def parent
      @parent
    end

    def name
      @name
    end

    # Public: access control on the collection
    #
    # actor: - The User to check permission for.
    # action - The Symbol action representing the level of permission to check for.
    #
    # Returns true or false.
    def permit?(actor, action)
      parent.permit?(actor, action) || super
    end

    # Public: access control on the collection
    #
    # Same as the permit? method above, but returns Promise<bool>
    #
    # actor: - The User to check permission for.
    # action - The Symbol action representing the level of permission to check for.
    def async_permit?(actor, action)
      parent.async_permit?(actor, action).then do |result|
        result || super
      end
    end

    # Internal: collections allow the same actors as their parent by default.
    def grant?(actor, action)
      parent.grant?(actor, action)
    end

    # Add access for an actor.
    #
    # actor - A User, or Installation
    #
    # Returns nothing.
    def add_actor(actor, action: :read)
      grant actor, action
    end

    # Remove access for a actor.
    #
    # actor - A User, or Installation
    #
    # Returns nothing.
    def remove_actor(actor)
      revoke actor
    end

    # Owner id for this collection
    def ability_id
      parent.id
    end

    # Reference to the collection type
    # a manufactured class-style name for reference purposes, e.g. Repository/Contents
    #
    # Returns a String
    def ability_type
      "#{@ability_type_prefix}/#{name}".freeze
    end
  end
end
