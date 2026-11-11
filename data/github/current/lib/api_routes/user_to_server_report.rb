# typed: true
# frozen_string_literal: true

class ApiRoutes::UserToServerReport
  NOT_APPLICABLE = [
    "Api::ImportIssues", # not officially documented in developer site
    "Api::CheckSuites", # currently in development
    "Api::CheckRuns", # currently in development
    "Api::Policies", # Internal API endpoints for creating S3 policies
  ]

  def self.collector
    ApiRoutes::ASTRouteCollector
  end

  attr_reader :collections
  def initialize(collections)
    @collections = collections
  end

  def print
    collections.each do |collection|
      next if NOT_APPLICABLE.any? { |namespace| collection.namespace == namespace }

      endpoints = collection.endpoints.select do |endpoint|
        endpoint.enabled_for_user_via_integrations? && endpoint.docs_url.present?
      end
      next if endpoints.empty?
      endpoints = endpoints.uniq(&:docs_url)

      list_items = endpoints.map do |endpoint|
        "* [%s%s](%s)" % [
          endpoint.docs_description[0].upcase,
          endpoint.docs_description[1..-1],
          endpoint.docs_url,
        ]
      end

      puts <<-TXT
#### #{collection.documentation_namespace}

#{list_items.join("\n")}

      TXT
    end
  end
end
