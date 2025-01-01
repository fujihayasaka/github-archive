# typed: true
# frozen_string_literal: true

class ApiRoutes::GranularPermissionsReport
  NOT_APPLICABLE = [
    "Api::BrowserReporting",
    "Api::Enterprise",
    "Api::Internal",
    "Api::Legacy",
    "Api::Staff",
    "Api::ThirdParty::Mailchimp",
    "Api::Admin", # GHE-only
    "Api::ImportIssues", # not officially documented in developer site
    "Api::CheckSuites", # currently in development
    "Api::CheckRuns", # currently in development
    "Api::Policies", # Internal API endpoints for creating S3 policies
  ]

  def self.collector
    ApiRoutes::ASTPermissionCollector
  end

  class PermissionCollection
    def self.for(permission)
      if permission == "metadata"
        MetadataPermissionCollection
      else
        PermissionCollection
      end.new(permission)
    end

    attr_reader :permission, :endpoints
    def initialize(permission, endpoints = [])
      @permission = permission
      @endpoints = endpoints
    end

    def commentary
      {
        "issues" => "Issues and pull requests are [closely related](/v3/issues/#list-issues). If your GitHub App has permissions on issues but not on pull requests, these endpoints will be limited to issues. Endpoints that return both issues and pull requests will be filtered. Endpoints that allow operations on both issues and pull requests will be restricted to issues.",
        "pull_requests" => "Issues and pull requests are [closely related](/v3/issues/#list-issues). If your GitHub App has permissions on pull requests but not on issues, these endpoints will be limited to pull requests. Endpoints that return both pull requests and issues will be filtered. Endpoints that allow operations on both pull requests and issues will be restricted to pull requests.",
      }[permission] || ""
    end

    def add(endpoint)
      @endpoints << endpoint
    end

    def header
      "Permission on \"#{permission}\""
    end

    def routes(items = endpoints)
      items.sort_by(&:verb_priority).uniq.sort.map do |endpoint|
        "- [`%s`](%s) (%s)" % [endpoint.to_docstyle, endpoint.docs_url, endpoint.permissions[permission].inspect]
      end
    end

    def sort_value
      permission
    end
  end

  class MetadataPermissionCollection < PermissionCollection
    def header
      "Metadata permissions"
    end

    def routes(items = endpoints)
      items.map do |endpoint|
        "- [`%s`](%s)" % [endpoint.to_docstyle, endpoint.docs_url]
      end
    end

    def commentary
      "These permissions are enabled for every app. These permissions are a collection of read only endpoints for accessing metadata for various resources that do not leak sensitive private repository information."
    end

    def sort_value
      "aaa" # force it to the front
    end
  end

  attr_reader :endpoints
  def initialize(collections)
    @endpoints = collections.reject do |collection|
      NOT_APPLICABLE.any? { |namespace| collection.namespace.start_with?(namespace) }
    end.map(&:endpoints).flatten.select do |endpoint|
      endpoint.enabled?
    end.reject do |endpoint|
      endpoint.docs_url.nil?
    end.each do |endpoint|
      if endpoint.permissions.length > 1
        endpoint.permissions.delete("metadata")
      end
    end
  end

  def print(out: STDOUT)
    permission_collections.sort_by(&:sort_value).each do |collection|
      out.puts "## #{collection.header.gsub("_", " ")}"
      out.puts
      unless collection.commentary.empty?
        out.puts collection.commentary
        out.puts
      end
      collection.endpoints.sort_by(&:subgroup).group_by(&:subgroup).each do |group, endpoints|
        unless group.empty?
          out.puts
          out.puts "_%s_" % group.capitalize
        end
        out.puts collection.routes(endpoints)
      end
      out.puts
    end
  end

  private

  def permission_collections
    endpoints.each_with_object({}) do |endpoint, collections_by_permission|
      endpoint.permissions.each_key do |name|
        collections_by_permission[name] ||= PermissionCollection.for(name)
        collections_by_permission[name].add(endpoint)
      end
    end.values
  end
end
