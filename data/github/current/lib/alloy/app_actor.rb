# typed: true
# frozen_string_literal: true

module Alloy
  class AppActor
    include GitHub::FlipperActor
    include GitHub::VexiActor

    attr_reader :flipper_id

    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    def initialize(index_key)
      @flipper_id = "#{self.class.name}:#{index_key}"
    end

    def to_s
      @flipper_id
    end
  end
end
