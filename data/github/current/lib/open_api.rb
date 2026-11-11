# typed: true
# frozen_string_literal: true

require "digest"

module OpenApi
  autoload :Description, "open_api/description"
  autoload :Validation, "open_api/validation"
  autoload :Router, "open_api/router"
  autoload :CLI, "open_api/cli"
  autoload :Transformer, "open_api/transformer"

  IGNORE_REASONS = [
    :deprecated,
    :experimental,
    :ignored,
    :internal,
    :unreleased,
    :we_forgot,
    :to_follow,
  ].freeze

  CURRENT_VERSION = "3.0.3"
  NEXT_VERSION    = "3.1.0"

  # A checksum of all operations, components and webhooks of our OpenAPI description
  # This is used by our scripts to make sure the root files are regenerated
  # whenever there is a change
  def self.checksum
    directories = [
      OpenApi.root.join("operations"),
      OpenApi.root.join("components"),
      OpenApi.root.join("config"),
      OpenApi.root.join("webhooks"),
    ]

    content = []

    directories.each do |dir|
      files = Dir["#{dir}/**/*"].sort.reject { |f| File.directory?(f) }
      files.each { |f| content << File.read(f) }
    end

    Digest::SHA256.hexdigest(content.join)
  end

  def self.root
    @root ||= GitHub::AppEnvironment.root.join("app/api/description")
  end

  def self.version(version = nil)
    if version.nil?
      raise "Invalid OpenApi release number set in OPENAPI_VERSION env var." unless [CURRENT_VERSION, NEXT_VERSION, nil].include?(ENV["OPENAPI_VERSION"])
      @version ||= ENV["OPENAPI_VERSION"] || CURRENT_VERSION
    else
      raise "Invalid OpenApi given: #{version}." unless [CURRENT_VERSION, NEXT_VERSION, nil].include?(version)
      @version = version
    end

    @version
  end

  def self.description(expand_references: false)
    @description ||= begin
      OpenApi::Description::Root.new(
        release.to_h(
          environment: OpenApi::Description::ReleaseWriter::ENV_INTERNAL,
          include_webhooks: GitHub.openapi_include_webhooks?,
          expand_references: expand_references,
        )
      )
    end
  end

  def self.release
    @release ||= begin
      OpenApi::Description::Release.parse(
        GitHub.openapi_release,
        include_unpublished: true,
        include_test_fixtures: GitHub.openapi_include_test_fixtures?,
        merge_ghec_operations: GitHub.openapi_merge_ghec_operations?,
      )
    end
  end

  def self.meta_schema
    JSON.parse(root.join("config/meta_schema.json").read)
  end

  def self.performing_transform?
    Transformer.transforming?
  end

  # Basic structure visitor pattern
  def self.visit(node, visitor)
    visitor.call(node)
    case node
    when Array
      node.each do |child|
        if child.is_a?(Hash)
          visit(child, visitor)
        end
      end
    when Hash
      node.each_value do |child|
        if child.is_a?(Hash)
          visit(child, visitor)
        end
      end
    end
  end

  # Starting with version 3.1 we support the top level "webhooks" key per OpenAPI spec
  # If no current_version is passed in, version from OPENAPI_VERSION env is used
  def self.webhook_key(current_version = self.version)
    if current_version == "3.0.3"
      return "x-webhooks"
    end
    "webhooks"
  end
end
