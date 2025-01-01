# typed: true
# frozen_string_literal: true

module Platform
  class MutationActor
    include GitHub::FlipperActor
    include GitHub::VexiActor

    attr_reader :flipper_id

    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    def initialize(mutation_class)
      @flipper_id = "#{self.class.name}:#{mutation_class.graphql_name}"
      @vexi_id = "#{self.class.name}:#{mutation_class.graphql_name}"
    end

    def to_s
      @flipper_id
    end

    def vexi_id
      @vexi_id
    end
  end
end
