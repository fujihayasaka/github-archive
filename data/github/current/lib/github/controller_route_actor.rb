# typed: true
# frozen_string_literal: true

module GitHub
  class ControllerRouteActor
    include GitHub::VexiActor

    # ID should be in the form of "controller_name-action_name"
    # e.g. "commits-show"
    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    def self.build(controller, action)
      raise ArgumentError, "controller and action must be present" if controller.blank? || action.blank?
      new("#{controller.gsub("/", "_")}-#{action}")
    end

    # e.g. "GET", "/repositories/:repository_id/contents(/*)?" => "GET__/repositories_/__d___/contents_/_.__"
    def self.build_api(http_method, api_route)
      id = "#{http_method} #{api_route}"
      sanitized_id = id.to_s.gsub(/[^a-zA-Z0-9\/._-]/, "_")
      new(sanitized_id)
    end

    # The controller_action passed as the

    # id argument should be in the form of "controller_name-action_name"
    # The Actor ID when adding an actor in devportal should be formatted "GitHub::ControllerRouteActor:controller_name-action_name"
    def initialize(id)
      @vexi_id = "#{self.class.name}:#{id}"
    end

    def to_s
      vexi_id
    end

    def vexi_id
      @vexi_id
    end
  end
end
