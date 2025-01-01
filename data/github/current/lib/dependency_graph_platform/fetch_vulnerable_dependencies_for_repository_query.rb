# typed: true
# frozen_string_literal: true

module DependencyGraphPlatform
  class FetchVulnerableDependenciesForRepositoryQuery

    class NullQuery
      sig { void }
      def execute_query! ; end
    end

    include GitHub::Memoizer

    sig { params(repo: Repository, client: DependencyGraphPlatform::Twirp::AlertingClient).void }
    def initialize(repo, client: DependencyGraphPlatform::Twirp::AlertingClient.new_fetch_client)
      @repo = repo
      @client = client
      @response = T.let(
        nil,
        T.nilable(Github::DependencyGraphPlatform::Alerting::V1::FetchVulnerableDependenciesForRepositoryResponse)
      )
    end

    sig { void }
    def execute_query!
      response
    end

    sig { returns(T::Array[DependencyGraph::Alerting::AlertableManifest]) }
    memoize def alertable_manifests
      response.manifests.map do |m|
        dependencies = m.alertable_dependencies.map do |d|
          vvrs = d.vulnerable_version_range_github_ids.map do |id|
            DependencyGraphPlatform::AlertableDependency::VulnerableVersionRange.new(github_id: id)
          end

          AlertableDependency.new(
            repository_id: @repo.id,
            requirements: d.requirements,
            scope: scope_to_string(d.scope),
            relationship: relationship_to_string(d.relationship),
            vulnerable_version_ranges: vvrs,
          )
        end

        AlertableManifest.new(
          path: m.path,
          name: m.filename,
          dependencies: dependencies,
        )
      end
    end

    private

    sig { returns(DependencyGraphPlatform::Twirp::AlertingClient) }
    attr_reader :client

    sig { returns(Github::DependencyGraphPlatform::Alerting::V1::FetchVulnerableDependenciesForRepositoryResponse) }
    def response
      @response ||= client.fetch_vulnerable_dependencies_for_repository(
        repository_id: @repo.id,
        commit_oid: @repo.default_oid,
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
        "unknown"
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
