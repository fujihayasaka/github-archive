# typed: true
# frozen_string_literal: true

# Allows hosts (e.g., github-fe123-cp1-prd.iad.github.net) to be used as
# Flipper actors.
module GitHub
  class FlipperHost
    include FlipperActor
    include VexiActor
    include GitHub::Relay::GlobalIdentification

    def self.local_host
      new(GitHub.local_host_name_short)
    end

    attr_reader :id

    # #to_s is used when recording actors in the audit log.
    alias_method :to_s, :id

    def initialize(hostname)
      @id = hostname

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
      "FeatureHost"
    end
  end
end
