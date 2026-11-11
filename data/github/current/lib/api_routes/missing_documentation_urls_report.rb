# typed: true
# frozen_string_literal: true

class ApiRoutes::MissingDocumentationUrlsReport
  SKIPPABLE_NAMESPACES = %w(
    Api::Internal
    Api::Staff
    Api::Policies
  )
  def self.collector
    ApiRoutes::ASTRouteCollector
  end

  attr_reader :collections
  def initialize(collections)
    @collections = collections
  end

  def print
    collections.each do |collection|
      if SKIPPABLE_NAMESPACES.any? { |namespace| collection.namespace.start_with?(namespace) }
        next
      end

      endpoints = collection.endpoints.select do |endpoint|
        endpoint.docs_url.nil?
      end
      next if endpoints.empty?

      title = collection.namespace.split("::").last.titleize
      list_items = endpoints.map do |endpoint|
        "* %s" % endpoint
      end

      puts <<-TXT
#### #{title}

#{list_items.join("\n")}

      TXT
    end
  end
end
