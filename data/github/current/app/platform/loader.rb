# typed: false
# frozen_string_literal: true

module Platform
  class Loader < GraphQL::Batch::Loader
    extend Platform::Objects::Base::MapToService

    class << self # rubocop:disable Style/ClassMethodsDefinitions ; each loader class that inherits from this class will have its own copy of this variable
      sig { returns(T.nilable(T::Array[T.class_of(ApplicationRecord::Base)])) }
      attr_accessor :replica_clusters

      sig { returns(T::Boolean) }
      def reads_from_replicas?
        replica_clusters.present?
      end

      def reset_replica_clusters!
        self.replica_clusters = nil
      end
    end

    delegate :replica_clusters, :reset_replica_clusters!, :reads_from_replicas?, to: :class, private: true

    DUMMY_MUTABLE_CONTEXT = {}

    def self.inherited(subclass)
      super
      subclass.underscored_name # prewarm #underscored_name cache at boot
    end

    def self.underscored_name
      @_underscored_name ||= self.name.demodulize.underscore
    end

    def self.for(*_arg0, **_arg1, &_arg2)
      if replica_clusters.nil?
        self.replica_clusters = Platform::GlobalScope.resolve_loaders_with_replicas
      else
        # we only fetch from replicas if all loaders were instantiated with
        # with a common value for the replica clusters we're gonna use later in `#perform`
        # if only one loader was instantiated without the needed replica cluster we'll fallback to the primary
        #
        # this is relevant for loaders used in both read and write contexts. Eg when executing a multiplexed mutations
        # see:
        # * https://github.com/github/github/pull/364037/files#r1979007412
        # * https://github.com/github/github/blob/77b5cd802f6a3bbe97fe7d7370e5484957112c2f/test/platform/read_mutation_fields_from_replicas_test.rb#L126-L170
        # for more details
        self.replica_clusters &= Platform::GlobalScope.resolve_loaders_with_replicas
      end

      super
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
      results = instrument do
        if reads_from_replicas?
          ActiveRecord::Base.connected_to_many(replica_clusters, role: :reading) do
            fetch(keys)
          end
        else
          fetch(keys)
        end
      end

      keys.each do |key|
        result = if results.is_a?(Promise)
          results.then { |r| r[key] }
        else
          results[key]
        end
        fulfill(key, result)
      end
    ensure
      reset_replica_clusters!
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
