# typed: true
# frozen_string_literal: true

# Allows sites (e.g., ash1-iad) to be used as Flipper actors.
module GitHub
  class FlipperSite
    include FlipperActor
    include VexiActor
    include GitHub::Relay::GlobalIdentification

    def self.site
      new(GitHub.site)
    end

    attr_reader :id

    # #to_s is used when recording actors in the audit log.
    alias_method :to_s, :id

    def initialize(site)
      @id = site.gsub(":", "_")

      freeze
    end

    def ==(other)
      self.class == other.class && id == other.id
    end
    alias_method :eql?, :==

    def self.find_by_id(id) #rubocop:disable GitHub/FindByDef
      new(id)
    end

    def platform_feature_name
      "FeatureSite"
    end
  end
end
