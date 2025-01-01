# typed: strict
# frozen_string_literal: true

module DependencyGraphPlatform
  class AllRepositoriesWithVersionRangeQuery

    class NullQuery
      include DependencyGraph::AllRepositoriesWithVersionRangeQueryInterface

      sig { override.void }
      def execute_query! ; end

      sig { override.returns(T::Array[DependencyGraph::Alerting::AlertableDependent]) }
      def alertable_dependents
        []
      end

      sig { override.returns(T.nilable(String)) }
      def last_cursor
        nil
      end

      sig { override.returns(T.nilable(String)) }
      def dependent_end_cursor
        nil
      end


      sig { override.returns(T::Boolean) }
      def has_next?
        false
      end
    end

    include GitHub::Memoizer
    include DependencyGraph::AllRepositoriesWithVersionRangeQueryInterface

    PAGE_SIZE = 100

    class Filter < T::Struct
      prop :ecosystem, String
      prop :package_name, String
      prop :requirements, String
      prop :cursor, T.nilable(String), default: nil

      sig { returns(T.nilable(T::Hash[Symbol, Integer])) }
      def parsed_cursor
        return unless cursor

        JSON.parse(T.must(cursor), symbolize_names: true)
      end
    end

    sig { params(filter: Filter, client: DependencyGraphPlatform::Twirp::AlertingClient).void }
    def initialize(filter:, client: DependencyGraphPlatform::Twirp::AlertingClient.new_reporting_client)
      @filter = filter
      @client = client
      @response = T.let(
        nil,
        T.nilable(Github::DependencyGraphPlatform::Alerting::V1::AllRepositoriesWithDependencyVersionResponse)
      )
    end

    sig { override.void }
    def execute_query!
      response
    end

    sig { override.returns(T::Array[DependencyGraph::Alerting::AlertableDependent]) }
    memoize def alertable_dependents
      response.repository_results.map do |repository_result|
        AlertableDependent.new(
          repository_id: repository_result.repository_id,
          path: repository_result.manifest_path,
          filename: repository_result.manifest_name,
          requirements: repository_result.requirements,
          scope: scope_to_string(repository_result.scope),
          relationship: relationship_to_string(repository_result.relationship),
          dgp_dependency_id: repository_result.dgp_dependency_id
        )
      end
    end

    sig { override.returns(T.nilable(String)) }
    memoize def last_cursor
      return nil unless response.next_cursor

      response.next_cursor.to_h.to_json
    end

    sig { override.returns(T.nilable(String)) }
    def dependent_end_cursor
      # This method is always nil for DGP as we do not return a cursor on each dependent, this interface is maintained
      # for compatibility with DependencyGraph::AllRepositoriesWithVersionRangeQuery for now but we should avoid
      # adding new call sites.
    end

    sig { override.returns(T::Boolean) }
    memoize def has_next?
      response.next_cursor.present?
    end

    private

    sig { returns(DependencyGraphPlatform::Twirp::AlertingClient) }
    attr_reader :client

    sig { returns(Filter) }
    attr_reader :filter

    sig { returns(Github::DependencyGraphPlatform::Alerting::V1::AllRepositoriesWithDependencyVersionResponse) }
    def response
      @response ||= client.all_repositories_with_dependency_version(
        ecosystem: filter.ecosystem,
        package_name: filter.package_name,
        requirements: filter.requirements,
        cursor: filter.parsed_cursor,
        limit: PAGE_SIZE,
      )
    end

    sig { params(twirp_scope: T.anything).returns(String) }
    def scope_to_string(twirp_scope)
      case twirp_scope
      when :SCOPE_RUNTIME
        "runtime"
      when :SCOPE_DEVELOPMENT
        "development"
      else
        # The database does not permit unknown to be stored,
        # so let's align to the legacy default of assuming
        # runtime when not defined.
        "runtime"
      end
    end

    sig { params(twirp_relationship: T.anything).returns(String) }
    def relationship_to_string(twirp_relationship)
      case twirp_relationship
      when :RELATIONSHIP_DIRECT
        "direct"
      when :RELATIONSHIP_TRANSITIVE
        "transitive"
      when :RELATIONSHIP_INCONCLUSIVE
        "inconclusive"
      else
        "unknown"
      end
    end
  end
end
