#!/usr/bin/env ruby
# typed: true
# frozen_string_literal: true

# generate-routing-schema-rate-limit-data.rb
#
# This script is the entrypoint for generating rate limit details for consumption by the API Gateway agent.
# It is used in conjunction with generate-routing-schema.rb, the date generated here is consumed by that script
# to create the final routing schema. We separated this script because generate-routing-schema runs in CI as well
# and this script brings in too many dependencies (it essentially loads the monolith) to run in that environment.
#
# So the workflow is to run the parent script -- generate-routing-schema-full.rb -- locally to generate both files
# CI will run only generate-routing-schema, but will fail the CI if diffs occur, q.v.
#
# See these other resources for more context on the Sinatra route resolution related to the REST API:
#
#  - lib/github/routers/api.rb - this converts requests to the internal representation (if needed) and resolves the
#                                API handler to process each request
#  - lib/open_api/router.rb - this file handles some OpenAPI validation of routes and converting to internal
#                             representations
#

require "json-schema"
require "sorbet-runtime"
require "yaml"
require_relative "route_generator"
require_relative "../config/environment"

# Ensure ROUTER is initialized
ROUTER = GitHub::Routers::Api.new(nil)

# RouteGenerator handles the reusable logic for generating route details to compose the end schema
module RateLimitGenerator
  extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig

  include Kernel

  # a generic lookup to replace placeholders defined in routes with stub values
  PLACEHOLDER_NAMES_TO_VALUES = T.let({
    "enterprise_id" => "1234",
    "repository_id" => "1234",
    "codeql_variant_analysis_id" => "1234",
    "variant_analysis_repo_id" => "1234",
    "pre_receive_hook_id" => "1234",
    "subject_digest" => "something",
    "check_suite_id" => "1234",
    "organization_id" => "1234",
    "client_id" => "foo",
    "secret_name" => "somesecret",
    "deployment_id" => "1234",
    "business_id" => "1234",
    "discussion_number" => "1234",
    "comment_number" => "1234",
    "hosted_runner_id" => "1234",
    "rolename" => "foo",
    "business_slug" => "foo",
    "comment_id" => "1234",
    "issue_number" => "123",
    "pull_number" => "123",
    "review_id" => "1234",
    "runner_id" => "1234",
    "attempt_number" => "1",
    "runner_group_id" => "1234",
    "image_definition_id" => "1234",
    "cache_id" => "1234",
    "execution_id" => "1234",
    "ref" => "cool-branch",
    "pre_receive_environment_id" => "1234",
    "image_version" => "v1",
    "org_id" => "1234",
    "access_token" => "some-token",
    "token_id" => "1234",
    "hook_id" => "1234",
    "team_id" => "1234",
    "user_id" => "1234",
    "run_id" => "1234",
    "artifact_id" => "1234",
    "gpg_key_id" => "1234",
    "key_id" => "1234",
    "security_feature" => "foo",
    "enablement" => "enable_all",
    "stream_id" => "1234",
    "authorization_id" => "1234",
    "cost_center_id" => "1234",
    "upload_id" => "1234",
    "check_run_id" => "1234",
    "fingerprint" => "foo",
    "assignment_id" => "1234",
    "classroom_id" => "1234",
    "key" => "foo",
    "target_user" => "hubot",
    "invitation_id" => "1234",
    "codespace_name" => "foo",
    "reminder_id" => "1234",
    "workspace_id" => "1234",
    "workflow_id" => "1234",
    "build_id" => "1234",
    "installation_id" => "1234",
    "required_workflow_id" => "1234",
    "ssh_signing_key_id" => "1234",
    "bypass_response_id" => "1234",
    "snapshot_id" => "1234",
    "basehead" => "main...feature",
    "alert_number" => "1234",
    "release_id" => "1234",
    "ruleset_id" => "1234",
    "version_id" => "1234",
    "column_id" => "1",
    "project_id" => "2",
    "card_id" => "2",
    "username" => "hubot",
    "role_id" => "1234",
    "entity_type" => "foo",
    "entity_id" => "1234",
    "network_id" => "1234",
    "host" => "foo",
    "guid" => "some-guid",
    "migration_id" => "1234",
    "integration_id" => "1234",
    "grant_id" => "1234",
    "app_id" => "1234",
    "asset_id" => "1234",
    "file_id" => "1234",
    "delivery_id" => "1234",
    "reaction_id" => "1234",
    "group_id" => "1234",
    "repo" => "gateway-authn-agent",
    "owner" => "github",
    "user" => "1234", # this might not be correct
    "id" => "1234",
    "name" => "foo",
    "bypass_request_number" => "1234",
    "org" => "foo",
    "app" => "foo",
    "slug" => "foo",
    "sha" => "deadbeef",
    "ghsa_id" => "1234",
    "version" => "deadbeef",
    "commit_id" => "deadbeef",
    "client" => "foo",
    "gist_id" => "1234",
    "network_settings_id" => "1234",
    "attachment_id" => "1234",
    "export_id" => "1234",
    "branch_policy_id" => "1234",
    "protection_rule_id" => "1234",
    "configuration_id" => "1234",
    "network_configuration_id" => "1234",
    "login" => "hubot",
    "environment" => "production",
    "environment_name" => "production",
    "external_identity_guid" => "some-value",
    "enterprise_or_org" => "foo",
    "custom_property_name" => "foo",
    "status_id" => "1234",
    "code" => "142ACE972ABA79A10624",
    "tag_id" => "1234",
    "knowledge_base_id" => "1234",
    "global_relay_id" => "1234",
    "upload_manifest_id" => "1234",
    "dismissal_request_number" => "1234",
    "language" => "ruby",
    "src_host" => "foo",
    "tag_protection_id" => "1234",
    "email" => "hello@example.com",
    "sarif_id" => "1234",
    "autolink_id" => "1234",
    "commit_sha" => "deadbeef",
    "analysis_id" => "1234",
    "in_reply_to_id" => "1234",
    "job_id" => "1234",
    "event_id" => "1234",
    "release_id_1" => "1234",
    "release_id_2" => "1234",
    "account_id" => "1234",
    "plan_id" => "1234",
    "milestone_number" => "14",
    "thread_id" => "1234",
    "campaign_number" => "1234",
    "pat_request_id" => "1234",
    "scale_set_id" => "1234",
    "package_type" => "npm",
    "package" => "foo",
    "author_id" => "1234",
    "oid" => "deadbeef",
    "rule_suite_id" => "1234",
    "action_owner" => "github",
    "action_name" => "stale",
    "version_sha" => "deadbeef",
    "issue_type_id" => "1234",
    "pat_id" => "1234",
    "session_id" => "1234",
    "template_repository_id" => "1234",
    "multi_part_upload_id" => "1234",
    "actor_type" => "user",
    "actor_id" => "1234",
    "credential_auth_id" => "1234",
    "/ref*" => "/1234",
    "/path*" => "/path",
    "/dir*" => "/dir",
    "/name*" => "/name"
  }, T::Hash[String, String]).sort_by { |key, _| key.length }.reverse # sorting by longest placeholder name first to ensure we don't clobber long placeholders with shorter ones

  def self.replace_external_placeholders_with_stub_values(path)
    current_path = path.dup

    PLACEHOLDER_NAMES_TO_VALUES.each do |key, value|
      current_path = current_path.gsub("{#{key}}", value)
    end

    if current_path.include?("{")
      # puts "problem with external route: #{current_path} still contains placeholders"
    end

    current_path
  end

  def self.replace_internal_placeholders_with_stub_values(path)
    current_path = path.dup

    PLACEHOLDER_NAMES_TO_VALUES.each do |key, value|
      current_path = current_path.gsub(":#{key}/", "#{value}/").gsub(":#{key}", value)
    end

    if current_path.include?(":")
      #puts "problem with internal route: #{path} - generated #{current_path} but it still contains placeholders"
    end

    current_path
  end

  def self.resolve_routes_to_namespace(method, paths)
    paths.each do |path|
      path_with_values = replace_external_placeholders_with_stub_values(path)
      hash = {
        "REQUEST_METHOD" => method,
        "PATH_INFO" => path_with_values,
        "rack.input" => StringIO.new,
      }

      ROUTER.select_app_without_instrumentation(hash)

      namespace = hash["process.api.controller"]
      return namespace, path unless namespace.nil? || namespace.empty?
    end

    [nil, paths.first]
  end

  ENTERPRISE_LOOKUP_MAP = {
    "Api::Enterprise::Actions" => [
      "/enterprise/actions-token",
    ],
    "Api::Enterprise::Announcement" => [
      "/enterprise/announcement",
    ],
    "Api::Enterprise::Avatars" => [
      "/enterprise/avatars/{login}",
      "/enterprise/avatars/b/{business_id}",
      "/enterprise/avatars/in/{integration_id}",
      "/enterprise/avatars/oa/{app_id}",
      "/enterprise/avatars/t/{team_id}",
      "/enterprise/avatars/u/{user_id}",
      "/enterprise/avatars/u/e"
    ],
    "Api::Enterprise::Contractors" => [
      "/enterprise/contractors",
      "/enterprise/contractors/{user_id}",
    ],
    "Api::Enterprise::Settings" => [
      "/enterprise/github/action_mailer",
      "/enterprise/github/environment",
      "/enterprise/settings/auth",
      "/enterprise/settings/cas",
      "/enterprise/settings/ldap",
      "/enterprise/settings/license",
      "/enterprise/settings/smtp",
    ],
    "Api::Enterprise::Stats" => [
      "/enterprise/stats/all",
      "/enterprise/stats/comments",
      "/enterprise/stats/gists",
      "/enterprise/stats/hooks",
      "/enterprise/stats/issues",
      "/enterprise/stats/milestones",
      "/enterprise/stats/orgs",
      "/enterprise/stats/pages",
      "/enterprise/stats/pulls",
      "/enterprise/stats/repos",
      "/enterprise/stats/users",
    ],
    "Api::Enterprise::Stats::SecurityProducts" => [
      "/enterprise/stats/security-products",
    ],
    "Api::Enterprise::Tokens" => [
      "/enterprise/tokens"
    ],
    "Api::Grants" => [
      "/applications/grants",
      "/applications/grants/{grant_id}"
    ]
  }

  sig { params(external_route: String, operation_id: String, namespace: String, resolved_namespace: String).returns(T::Boolean) }
  def self.report_issue_with_resolved_namespace(external_route, operation_id, namespace, resolved_namespace)
    if operation_id.start_with?("oauth-authorizations/") && namespace == "Api::Authorizations"
      # these are correct and an Enterprise-only feature, which is why it's not resolving as expected when the codepsace is setup in dotcom mode
      return false
    end

    if ENTERPRISE_LOOKUP_MAP.has_key?(namespace) && ENTERPRISE_LOOKUP_MAP[namespace].include?(external_route)
      # enterprise endpoint and routes are hard-coded and not available in dotcom mode
      return false
    end

    if external_route == "/internal/gists/{id}/git/pushes" && resolved_namespace == "Api::Root"
      # this resolver tries to validate a gist but it doesn't exist in the dev environment, so we don't
      return false
    end

    if external_route == "/internal/registry/package_enabled_status" && namespace == "Api::Internal::PackageRegistry"
      # this is a potential bug - this route doesn't seem to match correctly
      # ignoring for now as this is an internal-only route
      return false
    end

    if (external_route == "/(chunks|embeddings)" || external_route == "/(chunks|embeddings).*") && namespace == "Api::ServiceProxy"
      # some sort of bug here with how we're handling regexes in sinatra handlers - unblocking registering this route
      return false
    end

    namespace != resolved_namespace
  end

  sig { params(resolved_namespace: String, external_route: String, internal_route: String, method: String).returns(T.nilable(String)) }
  def self.resolve_rate_limit_family(resolved_namespace, external_route, internal_route, method)
    internal_route_with_values = replace_internal_placeholders_with_stub_values(internal_route)
    external_route_with_values = replace_external_placeholders_with_stub_values(external_route)

    hash = {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => internal_route_with_values, # first problem - this needs to be an internal route (with placeholders populated?)
      "github.api.route" => "#{method} #{internal_route}",
      "ORIGINAL_PATH_INFO" => external_route_with_values,
      "SERVER_NAME" => "api.github.com",
      "rack.input" => StringIO.new,
      "rack.url_scheme" => "https",
    }
    request = Sinatra::Request.new(hash)

    clazz = resolved_namespace.constantize
    app = clazz.new
    app.helpers.env = hash
    app.helpers.request = request
    app.helpers.response = Sinatra::Response.new # to allow error handling to complete if authentication fails and rejects our stub request

    app.helpers.params = {}

    GH::Context.enabled do
      # run the before filters to set the @links collection
      begin
        # puts "computing rate-limit family for #{resolved_namespace} - internal route #{internal_route} -> #{internal_route_with_values}"
        app.helpers.send(:filter!, :before)
      rescue UncaughtThrowError => ue
        # ignoring these errors as this is just Sinatra rejecting a reques with halt!
        # puts "error found while computing rate-limit family: #{ue} -> #{ue.class}"
      rescue StandardError => e
        puts "error found while setting filters: #{e} -> #{e.class} -> #{T.must(e.backtrace).join("\n\t")}"
        puts "computing rate-limit family for #{resolved_namespace} - internal route #{internal_route} -> #{internal_route_with_values}"
      end
    end

    begin
      # puts "computing rate-limit family for #{resolved_namespace} - internal route #{internal_route} -> #{internal_route_with_values}"
      configuration = app.helpers.send(:rate_limit_configuration)

      if configuration
        # puts "found family for #{resolved_namespace} - internal route #{internal_route} -> #{internal_route_with_values}: #{configuration.family}"
        return configuration.family
      end
    rescue UncaughtThrowError => ue
      # ignoring these errors as this is just Sinatra rejecting a reques with halt!
      # puts "error found while computing rate-limit family: #{ue} -> #{ue.class}"
    rescue StandardError => e
      puts "error found while reading rate_limit_configuration: #{e} -> #{e.class}"
      puts "computing rate-limit family for #{resolved_namespace} - internal route #{internal_route} -> #{internal_route_with_values}"
    end

    # puts "no rate-limit family found for #{resolved_namespace} - internal route #{internal_route} -> #{internal_route_with_values}"
    nil
  end

  sig { params(http_method: String, internal_route: String, external_routes: T::Array[String], operation_ids: String, namespace: String).returns([T::Boolean, T.nilable(String)]) }
  def self.determine_rate_limits(http_method, internal_route, external_routes, operation_ids, namespace)
    # we only need one of the routes to get the namespace, just use whichever on worked
    resolved_namespace, external_route = resolve_routes_to_namespace(http_method, external_routes)
    if resolved_namespace.nil?
      raise Exception, "- unable to resolve route to a namespace: #{external_route}"
    elsif report_issue_with_resolved_namespace(external_route, operation_ids, namespace, resolved_namespace)
      raise Exception, "- mismatch for: '#{http_method} #{external_route}' - got #{resolved_namespace} but expected #{namespace}"
    end

    skip_primary_rate_limit = Api::App.skipped_rate_limit_paths.include?(internal_route)

    primary_rate_limit_family = resolve_rate_limit_family(resolved_namespace, external_route, internal_route, http_method)

    if primary_rate_limit_family.nil? && internal_route.start_with?("/internal/") && resolved_namespace.start_with?("Api::Internal::")
      skip_primary_rate_limit = true
      primary_rate_limit_family = ""
    elsif !skip_primary_rate_limit && primary_rate_limit_family.nil? && resolved_namespace == "Api::BrowserReporting"
      skip_primary_rate_limit = true
      primary_rate_limit_family = ""
    # AuditLog routes are under a feature flag
    elsif !skip_primary_rate_limit && primary_rate_limit_family.nil? && resolved_namespace == "Api::AuditLog::Enterprise"
      skip_primary_rate_limit = true
      primary_rate_limit_family = ""
    elsif !skip_primary_rate_limit && primary_rate_limit_family.nil? && resolved_namespace == "Api::AuditLog::Organization"
      skip_primary_rate_limit = true
      primary_rate_limit_family = ""
    elsif !skip_primary_rate_limit && primary_rate_limit_family.nil? && resolved_namespace == "Api::AuditLog::Streams"
      skip_primary_rate_limit = true
      primary_rate_limit_family = ""
    elsif skip_primary_rate_limit && primary_rate_limit_family.nil? && resolved_namespace == "Api::GraphQL"
      # GraphQL has rate_limit_as nil set
      skip_primary_rate_limit = true
      primary_rate_limit_family = ""
    elsif !skip_primary_rate_limit && primary_rate_limit_family.nil? && resolved_namespace == "Api::Integrations"
      # Integrations has rate_limit_as nil set
      skip_primary_rate_limit = true
      primary_rate_limit_family = ""
    elsif !skip_primary_rate_limit && primary_rate_limit_family.nil? && resolved_namespace == "Api::RepositoryActionsRunners"
      # RepositoryActionsRunners has rate_limit_as Api::RateLimitConfiguration::ACTIONS_RUNNER_REGISTRATION_FAMILY set
      # but it throws trying to call `rate_limit_configuration` hardcoding for now
      skip_primary_rate_limit = false
      primary_rate_limit_family = "actions_runner_registration"
    elsif !skip_primary_rate_limit && primary_rate_limit_family.nil? && resolved_namespace == "Api::RepositoryCodeqlVariantAnalysisRepoTasksUpdate"
      # RepositoryCodeqlVariantAnalysisRepoTasksUpdate has rate_limit_as Api::RateLimitConfiguration::CODE_SCANNING_VARIANT_ANALYSIS_UPDATE_FAMILY set
      # but it throws trying to call `rate_limit_configuration` hardcoding for now
      skip_primary_rate_limit = false
      primary_rate_limit_family = "code_scanning_variant_analysis_update"
    elsif !skip_primary_rate_limit && primary_rate_limit_family.nil?
      raise Exception, "- unable to resolve primary rate limit family for #{resolved_namespace} - #{http_method} #{external_route}"
    end
    [skip_primary_rate_limit, primary_rate_limit_family]
  end
end

GATEWAY_PRIMARY_RATE_LIMIT_SCHEMA = {
  "type" => "object",
  "additionalProperties" => {
    "type" => "object",
    "additionalProperties" => {
      "type" => "object",
      "additionalProerties" => false,
      "required" => %w[skip_primary_rate_limit primary_rate_limit_family],
      "properties" => {
        "skip_primary_rate_limit" => {
          "type" => "boolean"
        },
        "primary_rate_limit_family" => {
          "type" => "string"
        }
      }
    }
  }
}

def validate_rate_limit_schema_definition!(hash)
  JSON::Validator.validate!(GATEWAY_PRIMARY_RATE_LIMIT_SCHEMA, hash)
end

if $PROGRAM_NAME == __FILE__
  # Enabling YJIT speeds up cache generation by about 25%
  RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enable)

  puts "Loading access entries..."
  access_entries = RouteGenerator.load_access_entries
  puts "Loaded #{access_entries.size} access entries"

  # Initialize lookup hash for route -> rate limit data
  rate_limit_data = {}

  puts "Processing routes to determine rate limit data..."
  access_entries.each do |access_entry|
    begin
      operation_ids = access_entry["operation_ids"]
      endpoint = access_entry["endpoint"]
      namespace = access_entry["namespace"]

      # Skip ignored routes
      if RouteGenerator::IGNORED_GHES_ROUTES.include?(endpoint)
        next
      end

      http_method, internal_route = endpoint.split(" ")
      if http_method.nil? || internal_route.nil?
        puts "Skipping invalid endpoint: #{endpoint}"
        next
      end

      # Resolve external routes for this internal route
      external_routes = RouteGenerator.resolve_external_routes(internal_route, operation_ids)
      if external_routes.empty?
        next
      end

      # Determine rate limits for this route
      begin
        skip_primary_rate_limit, primary_rate_limit_family = RateLimitGenerator.determine_rate_limits(http_method, internal_route, external_routes, operation_ids, namespace)

        # For each external route, add the rate limit data
        external_routes.each do |route|
          # Create the data structure for this route if it doesn't exist
          rate_limit_data[route] ||= {}

          # Store the rate limit data for this method
          rate_limit_data[route][http_method] = {
            "skip_primary_rate_limit" => skip_primary_rate_limit,
            "primary_rate_limit_family" => primary_rate_limit_family
          }
        end

        # Also handle internal route with placeholders
        internal_route_with_placeholders = RouteGenerator.convert_placeholders_to_external_representation(internal_route)
        if !RouteGenerator.regex_route?(internal_route_with_placeholders)
          rate_limit_data[internal_route_with_placeholders] ||= {}
          rate_limit_data[internal_route_with_placeholders][http_method] = {
            "skip_primary_rate_limit" => skip_primary_rate_limit,
            "primary_rate_limit_family" => primary_rate_limit_family
          }
        end
      rescue => e
        puts "Error determining rate limits for #{http_method} #{internal_route}: #{e.message}"
      end
    rescue => e
      puts "Error processing access entry #{access_entry.inspect}: #{e.message}"
    end
  end

  # Sort routes alphabetically
  puts "Sorting routes..."
  sorted_rate_limit_data = Hash[rate_limit_data.sort_by { |key, _| key }]

  puts "Validating schema..."
  validate_rate_limit_schema_definition!(sorted_rate_limit_data)

  # Define output path
  root_directory = File.expand_path("..", __dir__)
  output = File.join(root_directory, "app/api/gateway-routes-primary-rate-limits.yaml")

  puts "Writing rate limit data to #{output}"
  File.open(output, "w") do |file|
    file.puts("# This file contains rate limit data for API Gateway routes.")
    file.puts("# It is generated by script/generate-routing-schema-rate-limit-data.rb")
    file.puts("# Do not edit this file manually.")
    file.write(YAML.dump(sorted_rate_limit_data))
  end
  puts "Done!"
end
