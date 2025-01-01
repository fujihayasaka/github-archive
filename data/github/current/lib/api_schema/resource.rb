# typed: false
# frozen_string_literal: true
require "json_schema"
require "ecma-re-validator"

module ApiSchema
  class InvalidSchema < RuntimeError; end
  class SchemaNotFound < RuntimeError; end

  class Resource
    def self.load(path, store: JsonSchema::DocumentStore.new)
      ApiSchema::Config.with_ecmaregex do
        resource = new(JSON.parse(File.read(path)), path: path)
        resource.expand(store: store)
        resource
      end
    end

    attr_reader :schema, :path, :data
    def initialize(data, path: nil)
      @schema    = JsonSchema.parse!(data)
      schema.uri = schema.id
      @data      = data
      @path      = path
      @expanded  = false
    end

    def expanded?
      @expanded
    end

    def expand(store: JsonSchema::DocumentStore.new)
      return if expanded?

      ok, errors = schema.expand_references(store: store)
      if !ok
        msg = <<-MSG % name
Invalid schema %s

#{errors.join("\n")}
        MSG
        raise ApiSchema::InvalidSchema.new(msg)
      end
    end

    def validate(data:, rel: nil, route: nil)
      target = schema

      if route
        link = link_description_object(route: route, rel: nil)
        if link.nil?
          raise SchemaNotFound.new "No link definition object schema found for route '#{route}' for resource '#{name}'."
        end
        target = link.schema
      elsif rel
        # TODO(tornado): this is used only for looking up the new strict schemas to replace legacy schemas.
        # It can be removed on Nov 1 (or when we have no more integrators with the tornado feature flag.
        link = link_description_object(rel: rel, route: nil)
        if link.nil?
          raise SchemaNotFound.new "No link definition object schema found for rel '#{rel}' for resource '#{name}'."
        end
        target = link.schema
      end

      _, errors = target.validate(data)
      ApiSchema::ValidationResult.new(errors)
    end

    def link_description_object(rel:, route:)
      unless route
        return schema.links.find { |link| link.rel == rel }
      end

      verb, path = route.split(" ")
      method = verb.downcase.to_sym
      path = ApiSchema::Config::ROUTE_PATTERN_REPLACEMENTS.reduce(path) do |s, (k, v)|
        s.gsub(k, v)
      end
      uri_template = path.split("/").map { |segment| segment.start_with?(":") ? "{%s}" % segment.gsub(":", "") : segment }.join("/")
      schema.links.find { |link| link.method == method && link.href == uri_template }
    end

    def name
      File.basename(schema.id, ".json")
    end

    def each_property
      Array(data["definitions"]).each do |key, value|
        properties_in(key, value).each do |name, property|
          yield name, property
        end
      end

      Array(data["properties"]).each do |key, value|
        properties_in(key, value).each do |name, property|
          yield name, property
        end
      end

      Array(data["links"]).each do |link|
        next unless link["schema"]

        Array(link["schema"]["properties"]).each do |key, value|
          properties_in(key, value).each do |name, property|
            yield name, property
          end
        end
      end
    end

    private

    def properties_in(name, object)
      return {} if object["$ref"]
      return { name => object } if object["type"] != "object"

      properties = {}

      Array(object["properties"]).each do |key, value|
        next if !!value["$ref"]

        if value["type"] == "object"
          properties = properties.merge(properties_in(key, value))
        else
          properties = properties.merge({ key => value })
        end
      end
      properties
    end
  end

  # Represents the result of validating specific data against a specific schema.
  # Also hides the implementation details of JsonSchema::SchemaError and
  # JsonSchema::ValidationError, allowing us to expose the interface that best
  # suits our needs for working with schema validation errors.
  class ValidationResult
    # errors - An Array of JsonSchema::ValidationErrors.
    def initialize(errors)
      @errors = errors
      return if @errors.empty?

      sub_errors = errors.map(&:sub_errors).compact
      @errors = @errors.concat(sub_errors.flatten)
    end

    def valid?
      errors.empty?
    end

    def error_messages
      # TODO Once we publish our schema, consider using
      # `JsonSchema::SchemaError.aggregate(errors)` to produce error messages,
      # since it includes a reference to the schema that the request violated.
      # (https://github.com/interagent/committee uses that approach.)
      errors.map(&:message)
    end

    private

    attr_reader :errors
  end
end
