# typed: true
# frozen_string_literal: true

module Stratocaster
  # This class is used to allow us to create feature flags against Stratocaster
  # event types.
  #
  # This is currently used in Stratocaster::Event to allow us to turn off fanout for
  # certain event types during availability incidents.
  class EventTypeActor
    include GitHub::VexiActor
    attr_reader :flipper_id

    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    # The flipper_id includes the class name so it integrates with our flipper
    # actor storage and the internal GraphQL API.
    def initialize(event_type, action = nil)
      @flipper_id = "#{self.class.name}:#{event_type}"

      unless action.nil?
        @flipper_id += "_#{action}"
      end
    end

    def to_s
      @flipper_id
    end

    def vexi_id
      @flipper_id
    end

    def self.from_id(id)
      new(id)
    end
  end
end
