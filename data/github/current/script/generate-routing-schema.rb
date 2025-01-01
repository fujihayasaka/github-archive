#!/usr/bin/env ruby
# typed: true
# frozen_string_literal: true

# generate-routing-schema.rb
#
# This script is the entrypoint for generating routing details for consumption by the API Gateway agent.
#
# See these other resources for more context on the Sinatra route resolution related to the REST API:
#
#  - lib/github/routers/api.rb - this converts requests to the internal representation (if needed) and resolves the
#                                API handler to process each request
#  - lib/open_api/router.rb - this file handles some OpenAPI validation of routes and converting to internal
#                             representations
#

require "sorbet-runtime"
require "yaml"

# RouteGenerator handles the reusable logic for generating route details to compose the end schema
module RouteGenerator
  extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig

  include Kernel

  sig { params(value: T.nilable(T.any(TrueClass, FalseClass, String)), default_value: T::Boolean).returns(T::Boolean) }
  def self.parse_bool(value, default_value)
    if value.nil?
      return default_value
    end

    if value.is_a?(String)
      return true if value == "true"
      return false if value == "false"
      raise ArgumentError, "Invalid boolean value: #{value}"
    end

    value
  end

  IGNORED_GHES_ROUTES = [
    # this is a legacy route related to GHES pre-2.4 and is not documented
    "GET /internal/storage/github-enterprise-assets/:a/:b/:c/:d/:guid",
    "GET /internal/storage/github-enterprise-releases/:release_id_1/:release_id_2/:guid",
  ]

  sig { params(access_entry: T::Hash[String, String]).returns(T.nilable(RouteDefinition)) }
  def self.resolve_routes_for_schema(access_entry)
    operation_ids = T.must(access_entry["operation_ids"])
    service = T.must(access_entry["service"])
    allows_public_read = parse_bool(access_entry["allows_public_read"], false)

    endpoint = T.must(access_entry["endpoint"])

    if IGNORED_GHES_ROUTES.include?(endpoint)
      # escape hatch to ignore some routes that are legacy GHES only and not worth bringing along
      return nil
    end

    http_method, internal_route = endpoint.split(" ")
    if http_method.nil?
      raise Exception, "unable to parse method from endpoint: #{endpoint}"
    end
    if internal_route.nil?
      raise Exception, "unable to parse endpoint from endpoint: #{endpoint}"
    end

    route_metadata = RouteMetadata.new(
      operation_ids: operation_ids,
      http_method: T.must(http_method),
      catalog_service: "github/#{service}",
      allow_unauthenticated_access: allows_public_read,
    )

    if operation_ids == "ignored" && http_method == "POST" && internal_route == "/(chunks|embeddings)"
      # split this regex route into two unique routes to list independently
      return  RouteDefinition.new(
        routes: ["/chunks", "/embeddings"],
        metadata: route_metadata,
      )
    end

    if operation_ids == "ignored" && http_method == "GET" && internal_route == "/(chunks|embeddings).*"
      # split this regex route into two unique routes to list independently
      return  RouteDefinition.new(
        routes: ["/chunks{/path*}", "/embeddings{/path*}"],
        metadata: route_metadata,
      )
    end

    external_route = RouteGenerator::resolve_external_route(internal_route, operation_ids)
    if external_route.nil?
      return nil
    end

    routes = T.let([], T::Array[String])

    internal_route_with_placeholders = RouteGenerator::convert_placeholders_to_external_representation(internal_route)
    if internal_route_with_placeholders.nil?
      routes = [external_route]
    else
      if internal_route_with_placeholders.end_with?("{repo}/?*", "contents/?*")
        raise Exception, "unable to parse route: #{internal_route_with_placeholders} - this should not be hit!"
      end

      if internal_route_with_placeholders != external_route
        routes = [external_route, internal_route_with_placeholders]
      else
        routes = [external_route]
      end
    end


    RouteDefinition.new(
      routes: routes,
      metadata: route_metadata,
    )
  end

  EXTERNAL_ROUTE_OVERRIDES = T.let({
    # see https://github.com/github/api-gateway/blob/main/docs/gateway-route-schema.md#trailing-path-expression for context
    # this is something that the routing agent should support - matching on zero or more trailing segments after the `/contents/` segment
    "repos/create-or-update-file-contents" => "/repos/{owner}/{repo}/contents{/path*}",
    "repos/delete-file" => "/repos/{owner}/{repo}/contents{/path*}",
    "repos/get-content" => "/repos/{owner}/{repo}/contents{/path*}",
    # see https://github.com/github/api-gateway/blob/main/docs/gateway-route-schema.md#trailing-path-expression for context
    # this is something that the routing agent should support - matching on zero or more trailing segments after the `/contents/` segment
    "repos/get-readme,repos/get-readme-in-directory" => "/repos/{owner}/{repo}/readme{/dir*}",
    "repos/download-tarball-archive" => "/repos/{owner}/{repo}/tarball/{ref}",
    "repos/download-zipball-archive" => "/repos/{owner}/{repo}/zipball/{ref}",
  }, T::Hash[String, String])

  sig { params(route: String, old_prefix: String, new_prefix: String).returns(String) }
  def self.rewrite_route_as_external(route, old_prefix, new_prefix)
    remaining_chunk = route.sub old_prefix, ""
    remaining_chunk_with_placeholders = convert_placeholders_to_external_representation(remaining_chunk)
    "#{new_prefix}#{remaining_chunk_with_placeholders}"
  end

  sig { params(route: String, operation_id: String).returns(T.nilable(String)) }
  def self.resolve_external_route(route, operation_id)
    # handle routes using regexes first and convert into route-specific definition
    if EXTERNAL_ROUTE_OVERRIDES.has_key?(operation_id)
      return EXTERNAL_ROUTE_OVERRIDES[operation_id]
    end

    # remaining routes without placeholders should be served as-is
    unless route.include?(":")
      return route
    end

    # operations marked as deprecated should not have an external representation
    # the internal representation should still be listed
    if operation_id == "deprecated"
      return nil
    end

    if route.start_with?("/internal/")
      return convert_placeholders_to_external_representation(route)
    end

    if route.start_with?("/repositories/:repository_id")
      return rewrite_route_as_external(route, "/repositories/:repository_id", "/repos/{owner}/{repo}")
    elsif route.start_with?("/organizations/:organization_id")
      return rewrite_route_as_external(route, "/organizations/:organization_id", "/orgs/{owner}")
    elsif route.start_with?("/organizations/:org_id")
      return rewrite_route_as_external(route, "/organizations/:org_id", "/orgs/{owner}")
    elsif route.start_with?("/user/:user_id")
      return rewrite_route_as_external(route, "/user/:user_id", "/user/{user}")
    end

    convert_placeholders_to_external_representation(route)
  end

  INTERNAL_ROUTE_OVERRIDES = {
    # trailing path expression for internal storage expressions
    "/internal/storage/raw_lfs/:user/:repo/?*" => "/internal/storage/raw_lfs/{user}/{repo}{/path*}",
    "/internal/assets/media/:user/:repo/?*" => "/internal/assets/media/{user}/{repo}{/path*}",
    # rewrite regex for internal representation of repository contents
    "/repositories/:repository_id/contents/?*" => "/repositories/{repository_id}/contents{/path*}"
  }

  sig { params(path: String).returns(T.nilable(String)) }
  def self.convert_placeholders_to_external_representation(path)
    if INTERNAL_ROUTE_OVERRIDES.has_key?(path)
      return INTERNAL_ROUTE_OVERRIDES[path]
    end

    path.dup.gsub(/\/:([a-z_]+)/, "/{\\1}")
      .gsub("/branches/*", "/branches{/branch*}")
      .gsub("/commits/*/comments", "/commits/{commit_sha}/comments")
      .gsub("/commits/*", "/commits{/ref*}")
      .gsub("/git/extract-ref/*", "/git/extract-ref{/ref*}")
      .gsub("/git/matching-refs/*", "/git/matching-refs{/ref*}")
      .gsub("/git/refs/*", "/git/refs{/ref*}")
      .gsub("/git/ref/*", "/git/ref{/ref*}")
      .gsub("/git/tree-file-list/*", "/git/tree-file-list{/ref*}")
      .gsub("/git/trees/*", "/git/trees{/ref*}")
      .gsub("/statuses/*", "/statuses{/ref*}")
      .gsub("/status/*", "/status{/ref*}")
      .gsub("/releases/tags/*", "/releases/tags/{tag}")
      .gsub("/labels/*", "/labels{/name}")
      .gsub("/compare/*", "/compare/{basehead}")
  end

  class RouteMetadata < T::Struct
    const :operation_ids, String
    const :http_method, String
    const :catalog_service, String
    const :allow_unauthenticated_access, T::Boolean
  end

  class RouteDefinition < T::Struct
    const :routes, T::Array[String]
    const :metadata, RouteMetadata
  end
end

if $PROGRAM_NAME == __FILE__
  # Enabling YJIT speeds up cache generation by about 25%
  RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enable)

  root_directory = File.expand_path("..", __dir__)
  access_entrypoint_file = File.join(root_directory, "config/access_control/programmatic_access.yaml")

  access_entries_contents = File.open(access_entrypoint_file, "r")
  access_entries = YAML.safe_load(access_entries_contents, permitted_classes: [Symbol])

  lookup_by_route = T.let({}, T::Hash[String, T::Array[T::Hash[String, T.untyped]]])

  access_entries.each do |access_entry|
    result = RouteGenerator::resolve_routes_for_schema(access_entry)
    if result.nil?
      next
    end

    metadata = result.metadata

    result.routes.each do |route|
      route_contents = {
        "method" => metadata.http_method,
        "operation_ids" => metadata.operation_ids,
        "catalog_service" => metadata.catalog_service,
        "allow_unauthenticated_access" => metadata.allow_unauthenticated_access,
      }

      if lookup_by_route.has_key?(route)
        # append new hash to existing route
        current_value = T.must(lookup_by_route[route])
        current_value << route_contents

        lookup_by_route[route] = current_value
      else
        # create new entry for route using first hash for body
        lookup_by_route[route] = [route_contents]
      end
    end
  end

  # Add HEAD routes for all GET routes if they don't already exist
  # This is because Sinatra automatically registers HEAD routes for GET routes,
  # and the gateway should route these appropriately.
  routes_to_add = {}
  lookup_by_route.each do |route_path, route_configs|
    get_config = route_configs.find { |config| config["method"] == "GET" }
    head_exists = route_configs.any? { |config| config["method"] == "HEAD" }

    # If there's a GET route but no HEAD route, create a HEAD route with the same config
    if get_config && !head_exists
      # Create a deep copy of the GET config and change the method to HEAD
      head_config = get_config.transform_values { |v| v.is_a?(Hash) ? v.dup : v }
      head_config = head_config.dup
      head_config["method"] = "HEAD"

      # Add to the routes that need to be added
      routes_to_add[route_path] ||= []
      routes_to_add[route_path] << head_config
    end
  end

  # Add the new HEAD routes to the lookup
  routes_to_add.each do |route_path, configs|
    lookup_by_route[route_path] ||= []
    T.must(lookup_by_route[route_path]).concat(configs)
  end

  sorted_routes = Hash[lookup_by_route.sort_by { |key, _| key }]

  sorted_routes.each do |_, entries|
    entries.sort_by! { |entry| entry["method"] }
  end

  output = File.join(root_directory, "app/api/gateway-routes.yaml")

  YAML.dump(sorted_routes, File.open(output, "w"))
end
