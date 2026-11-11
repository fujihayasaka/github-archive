# typed: true
# frozen_string_literal: true

module Projects
  class StreamProcessorKeyActor
    include GitHub::VexiActor

    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(MemexProjectColumn::Interface::Indexable::Processor::Base::StreamProcessorKey.deserialize(id))
    end

    def initialize(key)
      @key = key
    end

    def id
      @key.serialize # "low_priority", "default"
    end
  end
end
