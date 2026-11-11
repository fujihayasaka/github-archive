# typed: true
# frozen_string_literal: true

module Platform
  class MutationActor
    include GitHub::VexiActor

    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    def initialize(mutation_class)
      @vexi_id = "#{self.class.name}:#{mutation_class.graphql_name}"
    end

    def to_s
      @vexi_id
    end

    def vexi_id
      @vexi_id
    end
  end
end
