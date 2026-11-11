# typed: true
# frozen_string_literal: true

module Repositories
  class Cache::NetworkByIdActor
    include GitHub::VexiActor

    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    def initialize(id)
      @vexi_id = "#{self.class.name}:#{id}"
    end

    def to_s
      @vexi_id
    end

    def vexi_id
      @vexi_id
    end
  end
end
