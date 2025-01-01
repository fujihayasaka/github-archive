# typed: true
# frozen_string_literal: true

module GitHub
  class ControllerRouteActor
    include GitHub::FlipperActor
    include GitHub::VexiActor

    attr_reader :flipper_id

    # ID should be in the form of "controller_name-action_name"
    # e.g. "commits-show"
    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    def self.build(controller, action)
      raise ArgumentError, "controller and action must be present" if controller.blank? || action.blank?
      new("#{controller.gsub("/", "_")}-#{action}")
    end

    # The controller_action passed as the

    # id argument should be in the form of "controller_name-action_name"
    # The flipper ID when adding an actor in devportal should be formatted "GitHub::ControllerRouteActor:controller_name-action_name"
    def initialize(id)
      @flipper_id = "#{self.class.name}:#{id}"
      @vexi_id = "#{self.class.name}:#{id}"
    end

    def to_s
      flipper_id
    end

    def vexi_id
      @vexi_id
    end
  end
end
