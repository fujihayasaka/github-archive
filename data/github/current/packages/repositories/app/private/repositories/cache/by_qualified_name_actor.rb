# typed: true
# frozen_string_literal: true

module Repositories
  class Cache::ByQualifiedNameActor
    include GitHub::VexiActor

    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    def initialize(id)
      @vexi_id = "#{self.class.name}:#{id}"
    end

    def self.build(nwo)
      raise ArgumentError, "nwo must be present" if nwo.blank?
      owner_name, name = nwo.split("/", 2)
      return nil if owner_name.blank? || name.blank?
      new("#{owner_name}-#{name}")
    end

    def to_s
      @vexi_id
    end

    def vexi_id
      @vexi_id
    end
  end
end
