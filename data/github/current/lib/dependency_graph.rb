# typed: true
# frozen_string_literal: true

module DependencyGraph
  autoload :Alerting, "dependency_graph/alerting"
  autoload :AllRepositoriesWithVersionRangeQueryInterface, "dependency_graph/all_repositories_with_version_range_query_interface"
  autoload :AllRepositoriesWithVersionRangeQuery, "dependency_graph/all_repositories_with_version_range_query"
  autoload :Backfill, "dependency_graph/backfill"
  autoload :Client, "dependency_graph/client"
  autoload :CrossServiceJob, "dependency_graph/cross_service_job"
  autoload :Dependency, "dependency_graph/dependency"
  autoload :Dependent, "dependency_graph/dependent"
  autoload :Manifest, "dependency_graph/manifest"
  autoload :ManifestsQuery, "dependency_graph/manifests_query"
  autoload :Package, "dependency_graph/package"
  autoload :PackageRelease, "dependency_graph/package_release"
  autoload :PackageReleaseDependent, "dependency_graph/package_release_dependent"
  autoload :PackageReleaseQuery, "dependency_graph/package_release_query"
  autoload :PackageReleaseVulnerabilitiesQuery, "dependency_graph/package_release_vulnerabilities_query"
  autoload :PackagesQuery, "dependency_graph/packages_query"
  autoload :Query, "dependency_graph/query"
  autoload :ReassignPackageMutation, "dependency_graph/reassign_package_mutation"
  autoload :RepositoriesUsingDependency, "dependency_graph/repositories_using_dependency"
  autoload :RepositoriesUsingDependenciesQuery, "dependency_graph/repositories_using_dependencies_query"
  autoload :RepositoryDependenciesClient, "dependency_graph/repository_dependencies_client"
  autoload :RepositoryDependenciesProvider, "dependency_graph/repository_dependencies_provider"
  autoload :RepositoryManifestsProvider, "dependency_graph/repository_manifests_provider"
  autoload :RepositoryDependenciesQuery, "dependency_graph/repository_dependencies_query"
  autoload :RepositoryOwnerDependenciesQuery, "dependency_graph/repository_owner_dependencies_query"
  autoload :RepositoryPackageReleaseLicense, "dependency_graph/repository_package_release_license"
  autoload :RepositoryPackageReleaseLicensesQuery, "dependency_graph/repository_package_release_licenses_query"
  autoload :RepositoryPackageReleaseQuery, "dependency_graph/repository_package_release_query"
  autoload :RepositoryPackageReleaseVulnerability, "dependency_graph/repository_package_release_vulnerability"
  autoload :RepositoryPackageReleaseVulnerabilitySeveritiesQuery, "dependency_graph/repository_package_release_vulnerability_severities_query"
  autoload :RepositorySBOMClient, "dependency_graph/repository_sbom_client"
  autoload :UnmappedPackagesQuery, "dependency_graph/unmapped_packages_query"
  autoload :UserTypeMiddleware, "dependency_graph/user_type_middleware"
  autoload :VulnerabilitiesQuery, "dependency_graph/vulnerabilities_query"

  def self.random_requirments
    operator = ["=", "~>", ">", "<", ">="].sample
    "#{operator} #{rand(10)}.#{rand(10)}.#{rand(10)}"
  end

  def self.stubbed_manifests(manifest_repo, repos)
    ::DependencyGraph::Manifest.wrap([
      {
        node: {
          id:           10,
          manifestType: :gemfile,
          filename:     "Gemfile",
          path:         "/",
          repositoryId: manifest_repo.id,
          dependencies: {
            totalCount: 5,
            pageInfo: {
              hasNextPage: false,
              hasPreviousPage: false,
              startCursor: "A",
              endCursor: "Z",
            },
            edges: repos.map do |repo|
              {
                node: {
                  id:              22,
                  requirements:    random_requirments,
                  packageName:     repo.name,
                  packageManager:  "RUBYGEMS",
                  packageId:       "10",
                  repositoryId:    repo.id,
                  hasDependencies: true,
                },
              }
            end.push({
              node: {
                requirements: "2.0.1",
                packageName:  "rake",
                packageId:    "nil",
                repositoryId: nil,
              },
            }),
          },
        },
      }.with_indifferent_access,
      {
        node: {
          id:           11,
          manifestType: :gemfile_lock,
          filename:     "Gemfile.lock",
          path:         "/",
          repositoryId: manifest_repo.id,
          dependencies: {
            totalCount: 5,
            pageInfo: {
              hasNextPage: false,
              hasPreviousPage: false,
              startCursor: "A",
              endCursor: "Z",
            },
            edges: repos.map do |repo|
              {
                node: {
                  id:              22,
                  requirements:    random_requirments,
                  packageName:     repo.name,
                  packageManager:  "RUBYGEMS",
                  packageId:       "10",
                  repositoryId:    repo.id,
                  hasDependencies: true,
                },
              }
            end.push({
              node: {
                requirements: "2.0.1",
                packageName:  "bleh",
                packageId:    "nil",
                repositoryId: nil,
              },
            }),
          },
        },
      }.with_indifferent_access,
    ],
    { first: 10 },
    ).push(DependencyGraph::Manifest.exceeds_max_size({
      "filename" => "package-lock.json",
      "path" => "",
      "repositoryId" => manifest_repo.id,
    }))
  end

  def self.stubbed_package_releases(params, repos)
    ::DependencyGraph::PackageRelease.wrap([
      {
        node: {
          packageName: params[:package_name],
          packageManager: params[:package_manager],
          version: params[:requirements].to_s.split(" ").last,
          dependencies: {
            totalCount: 5,
            edges: repos.map do |repo|
              {
                node: {
                  id:              22,
                  requirements:    random_requirments,
                  packageName:     repo.name,
                  packageManager:  "RUBYGEMS",
                  packageId:       "10",
                  repositoryId:    repo.id,
                  hasDependencies: true,
                },
              }
            end.push({
              node: {
                requirements: "2.0.1",
                packageName:  "rake",
                packageId:    "nil",
                repositoryId: nil,
              },
            }),
          },
        },
      }.with_indifferent_access,
    ])
  end

  def self.stubbed_packages(params, repos)
    return [] if params[:dependents_filter].blank?
    dependents = if params[:dependents_filter][:type] == :package
      [
        {
          cursor: "opaque-cursor",
          node: {
            name: "rails",
            repositoryId: repos.first.id,
          },
        },
        {
          cursor: "opaque-cursor",
          node: {
            name: "rake",
            repositoryId: nil,
          },
        },
      ]
    else
      repos.map do |repo|
        {
          cursor: "opaque-cursor",
          node: {
            name: repo.name,
            repositoryId: repo.id,
          },
        }
      end
    end

    packages = ::DependencyGraph::Package.wrap([
      {
        node: {
          id: "abc-123",
          name: "rails",
          packageManager: "RUBYGEMS",
          packageManagerHumanName: "RubyGems",
          abstractRepositoryDependents: {
            totalCount: repos.count,
          },
          abstractPackageDependents: {
            totalCount: 2,
          },
          dependents: {
            edges: dependents,
            pageInfo: {
              hasPreviousPage: false,
              hasNextPage: false,
            },
          },
        },
      }.with_indifferent_access,
      {
        node: {
          id: "def-456",
          name: "actionmailer",
          dependents: {
            edges: [],
            pageInfo: {
              hasPreviousPage: false,
              hasNextPage: false,
            },
          },
        },
      }.with_indifferent_access,
    ])

    if package_id = params[:package_filter][:package_id]
      packages.select! { |package| package.id == package_id }
    end

    packages.take(params.dig(:package_filter, :first) || 30)
  end

  HYDRO_LOW_LATENCY_MAX = 2000
  HYDRO_SYNC_MAX = 10

  # dynamically select a Hydro publisher depending on cardinality
  # of events the caller intends to publish
  def self.select_publisher(count)
    return GitHub.hydro_publisher if count.nil? || count <= 0 || count > HYDRO_LOW_LATENCY_MAX
    return GitHub.sync_hydro_publisher if count <= HYDRO_SYNC_MAX

    GitHub.low_latency_hydro_publisher
  end

  def self.check_feature_for_repo_or_owner(repository, flag_key)
    return false if GitHub.enterprise?
    return false unless repository && repository&.owner

    GitHub.flipper[flag_key].enabled?(repository) || GitHub.flipper[flag_key].enabled?(repository.owner)
  end

  def self.check_feature_for_user(user, flag_key)
    return false if GitHub.enterprise?
    return false unless user

    GitHub.flipper[flag_key].enabled?(user)
  end
end
