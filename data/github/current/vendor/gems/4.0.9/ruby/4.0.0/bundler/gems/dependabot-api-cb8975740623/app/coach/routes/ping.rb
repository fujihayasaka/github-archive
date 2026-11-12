# frozen_string_literal: true

require "renderer"

module Routes
  class Ping < Coach::Middleware
    uses Middlewares::Failbot, route_class: self

    def call
      Renderer.render("Dependabot OK - #{Time.now.utc.iso8601}")
    end
  end
end
