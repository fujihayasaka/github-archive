# typed: true
# frozen_string_literal: true

# Allows roles (e.g., github-lowworker) to be used as
# Flipper actors.
module GitHub
  class FlipperRole
    include FlipperActor
    include VexiActor
    include GitHub::Relay::GlobalIdentification

    def self.local_role
      new(GitHub.role.to_s)
    end

    attr_reader :id

    # #to_s is used when recording actors in the audit log.
    alias_method :to_s, :id

    def initialize(role)
      @id = role

      freeze
    end

    def ==(other)
      self.class == other.class && id == other.id
    end
    alias_method :eql?, :==

    def self.find_by_id(id)  # rubocop:disable GitHub/FindByDef
      new(id)
    end

    def platform_type_name
      "FeatureRole"
    end
  end
end
