# typed: true
# frozen_string_literal: true

class ApiRoutes::AuditReport
  NOT_APPLICABLE = [
    "Api::BrowserReporting",
    "Api::Enterprise",
    "Api::Internal",
    "Api::Legacy",
    "Api::Staff",
    "Api::ThirdParty::Mailchimp",
    "Api::Admin", # GHE-only
    "Api::Policies", # Internal API endpoints for creating S3 policies
  ]

  def self.collector
    ApiRoutes::ASTRouteCollector
  end

  attr_reader :skipped_collections, :collections
  def initialize(collections)
    @skipped_collections, @collections = collections.partition do |collection|
      NOT_APPLICABLE.any? do |namespace|
        collection.namespace.start_with?(namespace)
      end
    end

    # If any authorization keys have been used in enabled routes,
    # mark them as such so we can identify low-hanging fruit.
    @collections.map(&:endpoints).flatten.map(&:control_access_calls).flatten.
      select { |access_call| enabled_control_access_calls.include?(access_call.verb) }.
      map(&:enabled!)
  end

  def print
    collections.each do |collection|
      ApiRoutes::AuditFormatter.new(collection).print
    end

    puts "\n## Skipped" unless skipped_collections.empty?
    skipped_collections.each do |collection|
      puts "* \`%s\` (%d)" % [collection.namespace, collection.endpoints.count]
    end
  end

  private

  def enabled_control_access_calls
    @enabled_control_access_calls ||= collections.map(&:endpoints).flatten.
      select(&:enabled_for_integrations?).
      map(&:control_access_calls).flatten.map(&:name).uniq
  end
end
