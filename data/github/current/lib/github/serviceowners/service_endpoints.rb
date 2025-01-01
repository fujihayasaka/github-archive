# typed: true
# frozen_string_literal: true
module GitHub
  class Serviceowners
    class ServiceEndpoints
      # Datadog handles endpoints with regex in a strange way. We'd like this output to be compatible with datadog.
      # Since there are very few of these endpoints, just keep a map here.
      DATADOG_FORMATTED_REGEX_ENDPOINTS = {
        "/repositories/(\\d+)/readme(?:/(.*))?" => "_/repositories_/_d_/readme_:_/_.",
        "/repositories/(\\d+)/contents/(.+)" => "_/repositories_/_d_/contents_/_.",
        "/repositories/(\\d+)/tarball(?:/(.*))?" => "_/repositories_/_d_/tarball_:_/_.",
        "/repositories/(\\d+)/zipball(?:/(.*))?" => "_/repositories_/_d_/zipball_:_/_."
      }

      def initialize(json: false)
        @json = json
      end

      # Parses the codebase and service owner information to build an object representing all the route ownership of services.
      def build_service_endpoint_mapping(services: [])
        web_endpoints = find_web_endpoints
        api_endpoints = find_api_endpoints

        endpoints_by_service = api_endpoints.merge(web_endpoints) do |_key, api_routes, web_routes|
          web_routes + api_routes
        end

        endpoints_by_service.select! { |k, _| services.include?(k.to_sym) } if services.any?
        @json ? build_json(endpoints_by_service) : endpoints_by_service
      end

      private

      # build a datadog compatible json object from the output of build_service_endpoint_mapping
      def build_json(endpoints_by_service)
        output = {
          services: []
        }

        endpoints_by_service.each do |service, endpoints|
          output[:services] << {
            catalog_service: "github/#{service}",
            controllers: endpoints.group_by { |e| e.split(" ")[0] }.map do |controller, actions|
              controller_hash = {
                name: controller.underscore.delete_suffix("_controller").gsub("/", "_"),
                endpoints: []
              }

              actions.each do |a|
                _, methods, action = a.split(" ")
                methods.split("|").each do |m| # methods can be returned like "get|post"
                  controller_hash[:endpoints] << {
                    action: datadog_format(action),
                    method: m.downcase,
                    tags: {},
                  }
                end
              end

              controller_hash[:endpoints].sort_by! { |e| [e[:action], e[:method]] }
              controller_hash
            end.sort_by { |c| c[:name] }
          }
        end

        output[:services].to_json
      end

      def datadog_format(action)
        DATADOG_FORMATTED_REGEX_ENDPOINTS[action].presence || action.gsub("/*/", "/_/").gsub(/\?\*\z/, "*")
      end

      # Get all the ownership info for Api routes
      def find_api_endpoints
        endpoints = {}
        Zeitwerk::Loader.eager_load_all # everything needs to be loaded for ApiRoutes::Namespaces to work
        ApiRoutes::Namespaces.in(Api::App, filter: nil).each do |collection|
          collection&.endpoints&.each do |endpoint|
            route_str = "#{endpoint.verb.to_s.upcase} #{endpoint.route}"
            service = collection.namespace_class.service_mapping(route_str).to_s
            endpoints[service] ||= []
            endpoints[service] << "#{collection.namespace_class} #{route_str}"
          end
        end

        endpoints
      end

      # Get all the ownership info for web routes
      def find_web_endpoints
        endpoints = {}
        Rails.application.routes.routes.each do |route|
          controller, action = route.requirements[:controller], route.requirements[:action]
          next unless controller

          controller_class = (controller.to_s.camelize + "Controller").safe_constantize
          if controller_class.respond_to?(:service_mapping)
            service = controller_class.service_mapping(action).to_s
            endpoints[service] ||= []
            endpoints[service] << "#{controller_class} #{route.verb} #{action}"
            endpoints[service].uniq!
          end
        end

        endpoints
      end
    end
  end
end
