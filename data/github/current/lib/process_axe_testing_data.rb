#!/usr/bin/env safe-ruby
# typed: true
# frozen_string_literal: true
require "yaml"
require "digest"

class ProcessAxeTestingData
  # https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-general/file-io/#filesystem-access
  ALLOWED_REPORT_PATHS = [
    "/tmp/github-routes-for-axe-coverage-artifacts/snek_axe_routes_by_service.json",
    "snek_axe_routes_by_service.json",
    "/tmp/github-routes-for-axe-coverage-artifacts/routes_axe_coverage_by_service.json",
    "routes_axe_coverage_by_service.json",
    "/tmp/github-routes-for-axe-coverage-artifacts/axe_violations_by_service.json",
    "axe_violations_by_service.json",
  ].freeze

  def initialize(routes:, artifact_path:, final_routes_path:, output_directory: "", ownership_path: "ownership.yaml")
    @routes = routes
    @artifact_path = artifact_path
    @final_routes_path = final_routes_path
    @output_directory = output_directory
    @ownership_path = ownership_path
    @axe_violations_by_service = Hash.new { |h, k| h[k] = [] }
  end

  def generate_report
    routes_visited_by_axe = Set.new
    @axe_violations_by_service = Hash.new { |h, k| h[k] = [] }
    @service_names_by_hash ||= service_names_by_hash

    # Attribute axe route to a service
    File.readlines(@artifact_path).each do |line|
      line_to_json = JSON.parse(line)
      uri_path = URI::parse(line_to_json["url"]).path
      service = line_to_json["service"]
      service_hash = line_to_json["serviceHash"]
      route_pattern = URI::parse(line_to_json["routePattern"]).path

      # If service is empty, use the catalog service ID to look up the service name
      if service.empty?
        service = @service_names_by_hash.key(service_hash) || GitHub::ServiceMapping::UNKNOWN_SERVICE
      end
      matches = @routes.to_a.filter do |route|
        route.verb.include?("GET") && route.path.spec.to_s == route_pattern
      end
      match = matches.first

      controller = match && match.defaults ? match.defaults[:controller] : nil
      action = match && match.defaults ? match.defaults[:action] : nil

      if controller.nil? || action.nil?
        puts "URI: #{uri_path}"
        puts "Could not identify controller for route_pattern: #{route_pattern}"
        puts "Could not identify action for route_pattern: #{route_pattern}"
      end

      visited = { service: service, controller: controller, action: action, path: route_pattern }
      routes_visited_by_axe.add(visited)

      # Add axe violations to hash
      if line_to_json["violation"].present?
        axe_violations_to_hash(line_to_json, service)
      end
    end

    # Generate report on service by visited axe routes
    snek_axe_routes_by_service = routes_visited_by_axe.to_a.group_by { |h| h[:service] }
    write_report("snek_axe_routes_by_service.json", snek_axe_routes_by_service)

    # Generate report on service by axe routes coverage
    all_relevant_routes_by_service = JSON.parse(File.read(@final_routes_path))
    routes_axe_coverage_by_service = determine_routes_coverage_by_service(all_relevant_routes_by_service, snek_axe_routes_by_service)
    write_report("routes_axe_coverage_by_service.json", routes_axe_coverage_by_service)

    # Generate report on service by number of axe violations
    write_report("axe_violations_by_service.json", @axe_violations_by_service)
  end

  private

  def axe_violations_to_hash(json, service)
    # Store the number of axe violations for each route in the following format:
    # { violation_count: 1, violations: [ { violation_id: "color-contrast", impact: "critical",
    #   description: "Ensures the contrast between foreground and background colors meets WCAG 2 AA contrast ratio thresholds.",
    #   help: "Elements must have sufficient color contrast",
    #   help_url: "https://dequeuniversity.com/rules/axe/4.1/color-contrast?application=axeAPI",
    #   url_pattern: "https://github.com/" }]}

    axe_violation = json["violation"]

    # Is there already an entry for this service?
    if @axe_violations_by_service[service].empty?
      # Add a new one
      @axe_violations_by_service[service] = {
        service: service,
        violation_count: 1,
        violations: [{
        violation_id: axe_violation["id"],
        impact: axe_violation["impact"],
        description: axe_violation["description"],
        help: axe_violation["help"],
        help_url: axe_violation["helpUrl"],
        url_pattern: json["urlPattern"] }]
      }
    else
      # Update the existing entry
      @axe_violations_by_service[service][:violation_count] += 1
      @axe_violations_by_service[service][:violations] << {
        violation_id: axe_violation["id"],
        impact: axe_violation["impact"],
        description: axe_violation["description"],
        help: axe_violation["help"],
        helpUrl: axe_violation["helpUrl"],
        url_pattern: json["urlPattern"]
      }
    end

    @axe_violations_by_service
  end

  def determine_routes_coverage_by_service(all_relevant_routes_by_service, snek_axe_routes_by_service)
    all_relevant_routes_by_service.keys.map do |service|
      routes_for_service = all_relevant_routes_by_service[service]
      axe_routes = snek_axe_routes_by_service[service] || []
      axe_routes_path_patterns = axe_routes.map { |route| route[:path] }
      routes_with_axe_coverage = Set.new
      routes_without_axe_coverage = []
      routes_for_service.each do |route|
        if axe_routes_path_patterns.include?(route["path"])
          routes_with_axe_coverage.add(route)
        else
          routes_without_axe_coverage.push(route)
        end
      end

      coverage = {
        service: service,
        percentage: (axe_routes.size.to_f / routes_for_service.size.to_f) * 100,
        routes_with_axe_coverage: routes_with_axe_coverage.to_a,
        routes_without_axe_coverage: routes_without_axe_coverage
      }
      coverage
    end
  end

  def write_report(file_name, hash)
    report_output_path = "#{@output_directory}#{file_name}"
    if ALLOWED_REPORT_PATHS.include?(report_output_path)
      File.open(report_output_path, "w") do |f|
        f.write(JSON.pretty_generate(hash))
      end
    else
      raise "Report output path #{report_output_path} must be in ALLOWED_REPORT_PATHS"
    end
  end

  def service_names_by_hash
    ownership_yaml = YAML.safe_load(File.read(@ownership_path))
    services = ownership_yaml["ownership"]
    service_names_by_hash = {}
    salt = GitHub::ServiceMapping::HASH_SALT

    # Add hash of `unknown`, since it isn't part of the ownership file.
    unknown = GitHub::ServiceMapping::UNKNOWN_SERVICE
    service_names_by_hash[unknown] = Digest::SHA256.hexdigest("#{salt}#{unknown}")


    services.each do |service|
      service_name = service["name"]
      service_names_by_hash[service_name] = Digest::SHA256.hexdigest("#{salt}#{service_name}")
    end
    service_names_by_hash
  end
end
