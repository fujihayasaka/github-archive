# frozen_string_literal: true

require "renderer"

module Routes
  module Proxima
    class Sync < Coach::Middleware
      uses Middlewares::Failbot, route_class: self

      def call
        return Renderer.render_error(status: 404, title: "Not found") if Dependabot.proxima? || Dependabot.enterprise?

        Renderer.render(
          { ecosystem_versions: updater_versions }.to_json
        )
      end

      private

      def updater_versions
        UpdaterVersion.where(env: UpdaterVersion.envs[:prod]).order(ecosystem: :desc).map do |version|
          { ecosystem: version.ecosystem, version: version.version }
        end
      end
    end
  end
end
