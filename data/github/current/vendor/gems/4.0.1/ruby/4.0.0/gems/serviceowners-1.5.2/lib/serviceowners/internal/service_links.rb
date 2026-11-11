# typed: true
# frozen_string_literal: true

module Serviceowners
  module Internal
    # An internal class encapsulating the logic for generating service links
    class ServiceLinks
      def initialize(service)
        @service = service
      end

      def to_a
        links = %i[sentry datadog playbook].map do |method|
          send(method)
        end

        links.compact
      end

      private

      attr_reader :service

      def sentry
        {
          "name" => "#{service.human_name} Sentry",
          "description" => "Sentry issues #{description}",
          "kind" => "tool",
          "service" => service.qualified_name,
          "url" => "https://sentry.io/organizations/github/issues/?query=cause_catalog_service%3Agithub%2F#{service.name}"
        }
      end

      def datadog
        return unless (url = service.datadog_dashboard)

        {
          "name" => "#{service.human_name} Datadog Dashboard",
          "description" => "Datadog dashboard #{description}",
          "kind" => "dashboard",
          "service" => service.qualified_name,
          "url" => url
        }
      end

      def playbook
        return unless (url = service.playbook)

        {
          "name" => "#{service.human_name} Playbook",
          "description" => "Playbook #{description}",
          "kind" => "playbook",
          "service" => service.qualified_name,
          "url" => url
        }
      end

      def description
        return @description if defined?(@description)

        @description = "for the monolith's github/#{service.name} service"
      end
    end
  end
end
