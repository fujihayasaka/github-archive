# frozen_string_literal: true
#              

module Vexi
  module ActorCollection
    def self.from_base(base)
      if base.is_a?(Hash)
        HashActorCollection.new(base)
      elsif base.is_a?(Array)
        Adapters::ArrayActorCollection.new(base)
      else
        # Unknown type of actors, default to empty HashActorCollection
        HashActorCollection.new({})
      end
    end
  end
end
