# typed: true
# frozen_string_literal: true

# route generator is a shared module used by both generate-routing-schema.rb and
# generate-routing-schema-rate-limit-data to translate access entries
# into the schema used by the api-gateway.
# it is not executable by itself but has common logic for both scripts.

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

  def self.load_access_entries
    root_directory = File.expand_path("..", __dir__)
    access_entrypoint_file = File.join(root_directory, "config/access_control/programmatic_access.yaml")

    access_entries_contents = File.open(access_entrypoint_file, "r")
    access_entries = YAML.safe_load(access_entries_contents, permitted_classes: [Symbol])

    access_entries
  end

  IGNORED_GHES_ROUTES = [
    # this is a legacy route related to GHES pre-2.4 and is not documented
    "GET /internal/storage/github-enterprise-assets/:a/:b/:c/:d/:guid",
    "GET /internal/storage/github-enterprise-releases/:release_id_1/:release_id_2/:guid",

    # only enabled in the router for GitHub.enterprise?
    "GET /enterprise/stats/all",
    "GET /enterprise/stats/orgs",
    "GET /enterprise/stats/comments",
    "GET /enterprise/stats/gists",
    "GET /enterprise/stats/users",
    "GET /enterprise/stats/repos",
    "GET /enterprise/stats/pages",
    "GET /enterprise/stats/pulls",
    "GET /enterprise/stats/issues",
    "GET /enterprise/stats/milestones",

    # only enabled in the router for GitHub.enterprise?
    "GET /enterprise/stats/security-products",

    # all these routes have a `deliver_error! 404 unless Github.enterprise?` check
    "GET /enterprise/announcement",
    "PATCH /enterprise/announcement",
    "DELETE /enterprise/announcement",

    "GET /staff/audit_log/",

    "GET /enterprise/avatars/u/e",
    "GET /enterprise/avatars/:login",
    "GET /enterprise/avatars/u/:user_id",
    "GET /enterprise/avatars/oa/:app_id",
    "GET /enterprise/avatars/in/:integration_id",
    "GET /enterprise/avatars/t/:team_id",
    "GET /enterprise/avatars/b/:business_id",

    "PUT /user/:user_id/suspended",
    "DELETE /user/:user_id/suspended",

    "POST /enterprise/actions-token",

    # Api::Authorizations is only available when password auth is supported -> GHES
    "GET /authorizations",
    "GET /authorizations/:authorization_id",
    "POST /authorizations",
    "PUT /authorizations/clients/:client_id",
    "PUT /authorizations/clients/:client_id/:fingerprint",
    "PATCH /authorizations/:authorization_id",
    "POST /authorizations/:authorization_id",
    "DELETE /authorizations/:authorization_id",
  ]

  def self.regex_route?(route)
    # check if the route is a regex by looking for backslashes or pipe characters
    # this is a simple heuristic, but it works for our purposes
    route.include?("\\") || route.include?("|")
  end

  EXTERNAL_ROUTE_OVERRIDES = T.let({
    # see https://github.com/github/api-gateway/blob/main/docs/gateway-route-schema.md#trailing-path-expression for context
    # this is something that the routing agent should support - matching on zero or more trailing segments after the `/contents/` segment
    "repos/create-or-update-file-contents" => "/repositories/:repository_id/contents{/path*}",
    "repos/delete-file" => "/repositories/:repository_id/contents{/path*}",
    "repos/get-content" => "/repositories/:repository_id/contents{/path*?}",
    # see https://github.com/github/api-gateway/blob/main/docs/gateway-route-schema.md#trailing-path-expression for context
    # this is something that the routing agent should support - matching on zero or more trailing segments after the `/contents/` segment
    "repos/get-readme,repos/get-readme-in-directory" => "/repositories/:repository_id/readme{/dir*?}",
    "repos/download-tarball-archive" => "/repositories/:repository_id/tarball{/ref*?}",
    "repos/download-zipball-archive" => "/repositories/:repository_id/zipball{/ref*?}",
  }, T::Hash[String, String])


  # Define additional routes to include for this internal representation
  # each entry here should map to an entry in convert_natural_keys_to_ids
  ALIASES_FOR_ROUTE_EXPRESSIONS = T.let({
    # %r{^/internal/blackbird/users/([^/]+)\z}
    "/internal/blackbird/user/:user_id" => ["/internal/blackbird/users/:user_id"],

    # %r{^/internal/blackbird/repos/([^/]+)/([^/]+)(.*)}
    "/internal/blackbird/repositories/:repository_id" => ["/internal/blackbird/repos/:owner/:repo"],

    # %r{^/organizations/([^/]+)/settings/(.*)}
    "/organizations/:org_id/settings" => ["/orgs/:org_id/settings"],

    # %r{^/codespaces_internal/prebuilds/repository/([^/]+)/([^/]+)(.*)}
    "/codespaces_internal/prebuilds/repository/:repository_id" => ["/codespaces_internal/prebuilds/repository/:owner/:repo"],

    # %r{^/vscs_internal/codespaces/repository/([^/]+)/([^/]+)(.*)}
    "/vscs_internal/codespaces/repository/:repository_id" => ["/vscs_internal/codespaces/repository/:owner/:repo"],

    # %r{^/vscs_internal/repository/([^/]+)/([^/]+)(.*)}
    "/vscs_internal/repository/:repository_id" => ["/vscs_internal/repository/:owner/:repo"],

    # %r{^/admin/ldap/users/([^/]+)(.*)}
    "/admin/ldap/user/:user_id" => ["/admin/ldap/users/:user_id"],

    # %r{^/admin/organizations/([^/]+)(.*)}
    "/admin/organization/:org_id" => ["/admin/organizations/:name"],

    # %r{^/admin/users/([^/]+)(.*)}
    "/admin/user/:user_id" => ["/admin/users/:user_id"],

    # %r{^/staff/users/([^/]+)(.*)}
    "/staff/user/:user_id" => ["/staff/users/:user_id"],

    # %r{^/staff/orgs/([^/]+)(.*)}
    "/staff/organizations/:org_id" => ["/staff/orgs/:org_id"],

    # %r{^/internal/users/([^/]+)(.*)}
    "/internal/user/:user_id" => ["/internal/users/:user_id"],

    # %r{^/internal/orgs/([^/]+)(.*)}
    "/internal/organizations/:org_id" => ["/internal/orgs/:name"],

    # %r{^/internal/repositories/([^/]+)/([^/]+)/?\z}
    # %r{^/internal/repos/([^/]+)/([^/]+)(.*)}
    "/internal/repositories/:repository_id" => ["/internal/repositories/:owner/:repo", "/internal/repos/:owner/:repo"],

    # %r{^/internal/repositories/([^/]+)/([^/]+)(.*)/git/pushes\z}
    "/internal/repositories/:repository_id/git/pushes" => ["/internal/repositories/:owner/:repo/git/pushes"],
    "/internal/repositories/:repository_id/wiki/git/pushes" => ["/internal/repositories/:owner/:repo/wiki/git/pushes"],

    # %r{^/user/memberships/orgs/([^/]+)(.*)}
    "/user/memberships/organizations/:organization_id" => ["/user/memberships/orgs/:owner"],

    # %r{^/installations/(\d+)/repos/([^/]+)/([^/]+)(.*)}
    "/installations/:installation_id/repositories" => ["/installations/:installation_id/repos/:owner/:name"],

    # %r{^/orgs/([^/]+)/members/([^/]+)/codespaces/?([^/]+)?(.*)}
    "/organizations/:organization_id/members/:user_id/codespaces" => ["/orgs/:owner/members/:user_id/codespaces"],

    # %r{^/orgs/([^/]+)/members/([^/]+)/copilot/?([^/]+)?(.*)}
    "/organizations/:organization_id/members/:user_id/copilot" => ["/orgs/:owner/members/:user_id/copilot"],


    # %r{^/orgs/([^/]+)/team/([^/]+)/copilot/metrics(.*)}
    "/organizations/:organization_id/team/:team_id/copilot/metrics" => ["/organizations/:org_id/teams/:team_id/copilot/metrics"],

    # org teams routes
    "/organizations/:org_id/team/:team_id/discussion" => [
                                                # %r{^/organizations/(\d+)/teams/([^/]+)(.*)}
                                                "/organizations/:org_id/teams/:team_id/discussion",
                                                # %r{^/orgs/([^/]+)(/[^/]+)?/teams/([^/]+)(.*)}
                                                "/orgs/:owner/teams/:team_id/discussion",
                                                # deprecated API but router maps to Organization Teams routes
                                                # %r{^/teams/(\d+)(.*)}
                                                "/teams/:team_id/discussion",
    ],

    "/organizations/:org_id/team/:team_id/repositories/:repository_id" => [
                                                                            # external representation for teams is used
                                                                            # %r{^/organizations/(\d+)/teams/([^/]+)/repos/([^/]+)/([^/]+)(.*)}
                                                                            "/organizations/:org_id/teams/:team_id/repos/:owner/:repo",
                                                                            # %r{^/orgs/([^/]+)/teams/([^/]+)/repos/([^/]+)/([^/]+)(.*)}
                                                                            "/orgs/:owner/teams/:team_id/repos/:owner/:repo",
                                                                            # %r{^/organizations/(\d+)/team/(\d+)/repos/([^/]+)/([^/]+)(.*)}
                                                                            "/organizations/:org_id/team/:team_id/repos/:owner/:repo",
                                                                            # %r{^/orgs/([^/]+)/team/(\d+)/repos/([^/]+)/([^/]+)(.*)}
                                                                            "/orgs/:owner/team/:team_id/repos/:owner/:repo",

                                                                            # deprecated API but router maps to Organization Teams routes
                                                                            # %r{^/teams/(\d+)/repos/([^/]+)/([^/]+)(.*)}
                                                                            "/teams/:team_id/repos/:owner/:repo",
                                                                            "/teams/:team_id/repositories/:repository_id",
    ],
    "/organizations/:org_id/team/:team_id" => [
                                                # %r{^/organizations/(\d+)/teams/([^/]+)(.*)}
                                                "/organizations/:org_id/teams/:team_id",
                                                # %r{^/orgs/([^/]+)(/[^/]+)?/teams/([^/]+)(.*)}
                                                "/orgs/:owner/teams/:team_id",
                                                # deprecated API but router maps to Organization Teams routes
                                                # %r{^/teams/(\d+)(.*)}
                                                "/teams/:team_id",
                                              ],
    "/organizations/:organization_id/team/:team_id" => [
                                                          # %r{^/organizations/(\d+)/teams/([^/]+)(.*)}
                                                          "/organizations/:org_id/teams/:team_id",
                                                          # deprecated API but router maps to Organization Teams routes
                                                          # %r{^/teams/(\d+)(.*)}
                                                          "/teams/:team_id",
                                                        ],

    # organization roles routes
    "/organizations/:organization_id/organization-roles/team/:team_id/:role_id" => [
      # %r{^/orgs/([^/]+)(/[^/]+)?/teams/([^/]+)(.*)}
      "/orgs/:owner/organization-roles/teams/:team_id/:role_id",
    ],

    # security managers
    "/organizations/:organization_id/security-managers/team/:team_id" => [
      # %r{^/orgs/([^/]+)(/[^/]+)?/teams/([^/]+)(.*)}
      "/orgs/:owner/security-managers/teams/:team_id",
    ],

    # convert_inline_refs_to_trailing_refs maps commits to a ref with trailing /status to the statuses endpoint
    "/repositories/:repository_id/statuses/:sha" => [
      "/repositories/:repository_id/commits/:sha/statuses",
      "/repos/:owner/:repo/commits/:sha/statuses",
      "/repositories/:repository_id/commits/:sha/status",
      "/repos/:owner/:repo/commits/:sha/status",
    ],

    "/repositories/:repository_id/status/*" => [
      "/repositories/:repository_id/commits{/ref*}/status",
      "/repos/:owner/:repo/commits{/ref*}/status",
    ],

    "/repositories/:repository_id/statuses/*" => [
      "/repositories/:repository_id/commits{/ref*}/statuses",
      "/repos/:owner/:repo/commits{/ref*}/statuses",
    ],

    # convert_variant_analysis_repository_nwo_to_id
    # %r{^(?<prefix>/repositories/\d+/code-scanning/codeql/variant-analyses/\d+)/repos/(?<owner>[^/]+)/(?<name>[^/]+)(?<resource>/.*|$)}
    "/repositories/:repository_id/code-scanning/codeql/variant-analyses/:codeql_variant_analysis_id/repositories/:variant_analysis_repo_id" => [
      "/repositories/:repository_id/code-scanning/codeql/variant-analyses/:codeql_variant_analysis_id/repos/:variant_analysis_repo_owner/:variant_analysis_repo",
      "/repos/:owner/:repo/code-scanning/codeql/variant-analyses/:codeql_variant_analysis_id/repositories/:variant_analysis_repo_id",
      "/repos/:owner/:repo/code-scanning/codeql/variant-analyses/:codeql_variant_analysis_id/repos/:variant_analysis_repo_owner/:variant_analysis_repo",
    ],

    # %r{^/orgs/([^/]+)/attestations/(.*)}
    "/organizations/:org_id/attestations" => ["/orgs/:owner/attestations"],

    # %r{^/repos/([^/]+)(.*)/copilot_internal/embeddings_index}
    "/repositories/:repository_id/copilot_internal/embeddings_index" => [
      "/repos/{repo}/copilot_internal/embeddings_index",
    ],

    "/repositories/:repository_id/commits/*" => ["/repositories/{owner}/{repo}/commits/*"],

    # %r{^/repos/([^/]+)/([^/]+)(.*)}
    "/repositories/:repository_id" => ["/repos/{owner}/{repo}"],

    # %r{^/repos/([^/]+)/([^/]+)(.*)}
    "/repositories/:template_repository_id" => ["/repos/{owner}/{repo}"],

    # %r{^/orgs/([^/]+)(.*)}
    # added for multiple identifiers because we have different internal routes that use different names
    "/organizations/:organization_id" => ["/orgs/:owner"],
    "/organizations/:org_id" => ["/orgs/:owner"],

    # %r{^/users/([^/]+)(.*)}
    "/user/:user_id" => ["/users/:user"],

    # %r{^/apps/([^/]+)(.*)}
    "/app/:app_id" => ["/apps/:app_slug"],

    "/runtime/:environment_id/snapshot/" => ["/runtime/:environment_id/snapshot{/path*?}"],
  }, T::Hash[String, T::Array[String]])

  # These deprecated routes are still observed in the wild in the REST API, and until we block them we should
  # publish them to the gateway routing agent.
  ALLOWED_DEPRECATED_ROUTES = T.let([
    "/legacy/user/search/:q",
    "/legacy/repos/search/:q",
    "/legacy/issues/search/:owner/:repo/:state/:q",
    "/repositories/:repository_id/import/issues/:issue_id",
    "/repositories/:repository_id/git/refs",
    "/repositories/:repository_id/watchers",
    "/repositories/:repository_id/hooks/:hook_id/test",
    "/user/subscriptions/:owner/:repo",
    "/user/:user_id/watched",
  ], T::Array[String])

  sig { params(route: String, old_prefix: String, new_prefix: String).returns(String) }
  def self.rewrite_route_with_prefix(route, old_prefix, new_prefix)
    remaining_chunk = route.sub old_prefix, ""
    "#{new_prefix}#{remaining_chunk}"
  end

  sig { params(route: String, operation_id: String).returns(T::Array[String]) }
  def self.resolve_external_routes(route, operation_id)
    # handle routes using regexes first and convert into route-specific definition
    if EXTERNAL_ROUTE_OVERRIDES.has_key?(operation_id)
      route = T.must(EXTERNAL_ROUTE_OVERRIDES[operation_id])
    end

    if operation_id == "ignored" && route == "/(chunks|embeddings)"
      # split this regex route into two unique routes to list independently
      return ["/chunks", "/embeddings"]
    end

    if operation_id == "ignored" && route == "/(chunks|embeddings).*"
      # split this regex route into two unique routes to list independently
      return ["/chunks{/path*}", "/embeddings{/path*}"]
    end

    # remaining routes without placeholders should be served as-is
    unless route.include?(":")
      return [route]
    end

    # operations marked as deprecated should not have an external representation
    # the internal representation should still be listed
    if operation_id == "deprecated" && !ALLOWED_DEPRECATED_ROUTES.include?(route)
      return []
    end

    routes = T.let([route], T::Array[String])

    # Find the first matching pattern and apply the transformation
    ALIASES_FOR_ROUTE_EXPRESSIONS.each do |internal_pattern, external_pattern|
      routes.each do |route|
        if route.start_with?(internal_pattern)
          additional_routes = external_pattern.map do |pattern|
            rewrite_route_with_prefix(route, internal_pattern, pattern)
          end

          routes = routes.concat(additional_routes)

          break
        end
      end
    end

    routes.map { |route| convert_placeholders_to_external_representation(route) }.uniq
  end

  INTERNAL_ROUTE_OVERRIDES = {
    # trailing path expression for internal storage expressions
    "/internal/storage/raw_lfs/:user/:repo/?*" => "/internal/storage/raw_lfs/{user}/{repo}{/path*?}",
    "/internal/assets/media/:user/:repo/?*" => "/internal/assets/media/{user}/{repo}{/path*?}",
    # rewrite regex for internal representation of repository contents
    "/repositories/:repository_id/contents(/*)?" => "/repositories/{repository_id}/contents{/path*?}"
  }

  sig { params(path: String).returns(String) }
  def self.convert_placeholders_to_external_representation(path)
    if INTERNAL_ROUTE_OVERRIDES.has_key?(path)
      return T.must(INTERNAL_ROUTE_OVERRIDES[path])
    end

    path.dup.gsub(/\/:([a-z_]+)/, "/{\\1}")
      .gsub("/branches/*", "/branches{/branch*}")
      .gsub("/commits/*", "/commits{/ref*}")
      .gsub("/git/extract-ref/*", "/git/extract-ref{/ref*}")
      .gsub("/git/matching-refs/*", "/git/matching-refs{/ref*}")
      .gsub("/git/refs/*", "/git/refs{/ref*}")
      .gsub("/git/ref/*", "/git/ref{/ref*}")
      .gsub("/git/tree-file-list/*", "/git/tree-file-list{/ref*}")
      .gsub("/git/trees/*", "/git/trees{/ref*}")
      .gsub("/statuses/*", "/statuses{/ref*}")
      .gsub("/status/*", "/status{/ref*}")
      .gsub("/releases/tags/*", "/releases/tags{/tag*}")
      .gsub("/labels/*", "/labels{/name*}")
      .gsub("/compare/*", "/compare{/basehead*}")
  end

  class RouteMetadata < T::Struct
    const :backend_route, T.nilable(String)
    const :operation_ids, String
    const :http_method, String
    const :catalog_service, String
    const :allow_unauthenticated_access, T::Boolean
    const :skip_primary_rate_limit, T::Boolean
    const :primary_rate_limit_family, String
  end

  class RouteDefinition < T::Struct
    const :routes, T::Array[String]
    const :metadata, RouteMetadata
  end
end
