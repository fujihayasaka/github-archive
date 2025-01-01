# typed: false
# frozen_string_literal: true

module Platform
  class Loader < GraphQL::Batch::Loader
    extend Platform::Objects::Base::MapToService

    DUMMY_MUTABLE_CONTEXT = {}

    def self.inherited(subclass)
      super
      subclass.underscored_name # prewarm #underscored_name cache at boot
    end

    def self.underscored_name
      @_underscored_name ||= self.name.demodulize.underscore
    end

    def instrument
      current_query_info = Platform::GlobalScope.queries.last

      Platform::LoaderTracker.track_loader(self) do
        # If graphql loaders are called outside graphql, don't override the context
        if !current_query_info.present?
          yield
        else
          GitHub::ServiceMapping.push_graphql_service_mapping_context(self.class, current_query_info[:query].context) do
            yield
          end
        end
      end
    end

    def perform(keys)
      results = instrument { fetch(keys) }
      keys.each do |key|
        result = if results.is_a?(Promise)
          results.then { |r| r[key] }
        else
          results[key]
        end
        fulfill(key, result)
      end
    end

    def fetch(keys)
      raise Platform::Errors::NotImplemented, "Implement this method in subclasses only."
    end

    def self.method_added(method_name)
      if method_name == :perform
        raise Errors::Internal, "Heya! You should define #fetch in subclasses of Platform::Loader instead of #perform"
      end
    end

    def dog_tags
      ["catalog_service:#{GitHub::ServiceMapping.catalog_service_name(self.class.service_mapping)}"]
    end

    def graphql_tags
      current_query_info = Platform::GlobalScope.queries.last
      if current_query_info.present?
        variables = current_query_info[:variables]
        if variables && variables["track_graphql_tags"]&.is_a?(Array)
          return variables["track_graphql_tags"]
        end
      end

      []
    end
  end
end
