# typed: strict
# frozen_string_literal: true

module Alloy
  class AppActor
    include GitHub::FlipperActor
    include GitHub::VexiActor

    sig { override.returns(String) }
    attr_reader :flipper_id
    alias :vexi_id :flipper_id

    sig { params(id: T.any(String, Symbol)).returns(Alloy::AppActor) }
    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    sig { params(index_key: T.any(String, Symbol)).void }
    def initialize(index_key)
      @flipper_id = T.let("#{self.class.name}:#{index_key}", String)
    end

    sig { returns(String) }
    def to_s
      @flipper_id
    end
  end
end
