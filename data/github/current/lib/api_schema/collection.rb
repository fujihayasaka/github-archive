# typed: true
# frozen_string_literal: true

require "api_schema/resource"
require "api_schema/config"

module ApiSchema
  class Collection
    def self.load(dir, store: JsonSchema::DocumentStore.new)
      collection = new(store: store)

      ApiSchema::Config.with_ecmaregex do
        Dir["#{dir}/**/*.json"].each do |path|
          resource = ApiSchema::Resource.new(JSON.parse(File.read(path)), path: path)
          store.add_schema(resource.schema)
          collection.add(resource)
        end
      end

      collection
    end

    attr_reader :store
    def initialize(store: JsonSchema::DocumentStore.new)
      @store = store
      @by_name = {}
    end

    def validate(resource:, data:, rel: nil, route: nil)
      resource(resource).validate(data: data, rel: rel, route: route)
    end

    def each(&block)
      @by_name.values.each(&block)
    end

    def add(resource)
      @by_name[resource.name.downcase] = resource
    end

    def resource(name)
      schema = @by_name[name.downcase]
      schema.expand(store: store)
      schema
    end
  end
end
