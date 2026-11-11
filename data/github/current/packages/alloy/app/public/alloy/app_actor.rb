# typed: strict
# frozen_string_literal: true

module Alloy
  class AppActor
    include GitHub::VexiActor

    sig { override.returns(String) }
    attr_reader :vexi_id

    sig { params(id: T.any(String, Symbol)).returns(Alloy::AppActor) }
    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    sig { params(index_key: T.any(String, Symbol)).void }
    def initialize(index_key)
      @vexi_id = T.let("#{self.class.name}:#{index_key}", String)
    end

    sig { returns(String) }
    def to_s
      @vexi_id
    end
  end
end
