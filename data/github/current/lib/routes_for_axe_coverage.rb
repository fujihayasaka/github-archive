#!/usr/bin/env safe-ruby
# typed: true
# frozen_string_literal: true

require "uri"
require "method_source"
require "json"

class RoutesForAxeCoverage
  # https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-general/file-io/#filesystem-access
  ALLOWED_REPORT_PATHS = [
    "/tmp/github-routes-for-axe-coverage-artifacts/programatically_considered_routes.json",
    "programatically_considered_routes.json",
    "/tmp/github-routes-for-axe-coverage-artifacts/programatically_excluded_routes.json",
    "programatically_excluded_routes.json",
    "/tmp/github-routes-for-axe-coverage-artifacts/final_routes_list.json",
    "final_routes_list.json"
  ].freeze

  MANUAL_EXCLUSION_PATH = "script/accessibility/exclude_from_axe_coverage.json"

  def initialize(routes:, output_directory: "")
    @routes = routes
    @output_directory = output_directory
  end

  def generate_report
    get_routes_that_need_axe_coverage = Set.new
    excluded_get_routes = Set.new

    @routes.select do |route|
      controller = route.defaults[:controller] || nil
      action = route.defaults[:action] || nil
      controller_constantized = controller ? "#{controller}_controller".camelize.safe_constantize : nil
      if controller_constantized
        begin
          service = controller_constantized&.new.try(:logical_service)
        rescue NoMethodError, TypeError => e
          # Unable to call `logical_service` if it's dependent on app environment context (e.g. codesearch_controller, internal_graphl_controller)
          # The Axe data may fill in some gap here, since it has access to `logical_service`.
          service = "unknown"
        end
      end
      service ||= "unknown"

      reason_to_exclude = reason_to_exclude_route(controller, action, controller_constantized)
      route_data = {  controller: controller, action: action, path: route.path.spec.to_s, service: service }
      if reason_to_exclude
        route_data[:reason_to_exclude] = reason_to_exclude
        excluded_get_routes.add(route_data)
      else
        get_routes_that_need_axe_coverage.add(route_data)
      end
    end

    manually_excluded_routes = JSON.parse(File.read(MANUAL_EXCLUSION_PATH))
    if manually_excluded_routes.present?
      final_routes = get_routes_that_need_axe_coverage.reject do |route|
        manually_excluded_routes.find { |r| r["path"] == route[:path] }.present?
      end
    else
      final_routes = get_routes_that_need_axe_coverage
    end

    write_report("programatically_considered_routes.json", group_by_service(get_routes_that_need_axe_coverage))
    write_report("programatically_excluded_routes.json", group_by_service(excluded_get_routes))
    write_report("final_routes_list.json" , group_by_service(final_routes))
  end

  def controller_to_skip?(controller)
    controller.starts_with?("rails/") || controller == ("component_previews") || controller == "" || controller == "internal_graphql"
  end

  def reason_to_exclude_route(controller, action = nil, controller_constantized = nil)
    if controller_constantized && controller_constantized.action_methods.include?(action) && controller_constantized&.new.method(action).methods.include?(:source)
      controller_action_source = controller_constantized&.new.method(action)&.source
    end
    if !controller
      "Controller does not exist"
    elsif controller_to_skip?(controller)
      "Controller #{controller} is not a user facing controller"
    elsif controller_constantized
      if controller_constantized._layout == false
        "Controller #{controller} has layout set to false and was determined to not correspond to a full page"
      elsif !controller_constantized.action_methods.include?(action)
        "Action is not defined"
      elsif !controller_action_source.include?("render ") && !controller_action_source.include?("render_react_app")
        "Route does not render any content"
      elsif (!controller_action_source.include?(".html ") && controller_action_source.include?("layout: false")) ||
        (!controller_action_source.include?(".html ") && controller_action_source.include?("head ")) ||
        (!controller_action_source.include?(".html ") && controller_action_source.include?("render partial:")) ||
        (!controller_action_source.include?(".html ") && controller_action_source.include?("respond_to "))
        "Route was determined to not correspond to a full page"
      end
    end
  end

  private

  def group_by_service(hash)
    hash.to_a.group_by { |h| h[:service] }
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
end
