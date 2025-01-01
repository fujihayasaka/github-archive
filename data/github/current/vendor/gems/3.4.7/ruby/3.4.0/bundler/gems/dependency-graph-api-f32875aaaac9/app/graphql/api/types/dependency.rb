module API
  module Types
    class Dependency < Types::BaseObject

      ALLOWED_MAVEN_MAPPING_CERTAINTIES = [
        ::PackageToRepoMapping::Certainty::OVERRIDE,
        ::PackageToRepoMapping::Certainty::POSITIVE_MATCH,
        ::PackageToRepoMapping::Certainty::MATCHING_MANIFEST,
        ::PackageToRepoMapping::Certainty::CLEARLY_DEFINED_MATCH,
      ]

      description "A dependency"

      implements GraphQL::Types::Relay::Node

      global_id_field :id

      field :repository_id, Integer, null: true

      def repository_id
        if object.respond_to?(:package_github_repository_id)
          if object.respond_to?(:package_github_repository_id_certainty) && object.respond_to?(:package_manager)
            Instrument.increment("package_to_repo_mapping.viewed",
                                 package_manager: object.package_manager,
                                 certainty: object.package_github_repository_id_certainty || 0
            )

            # HACK: We don't want to show the repo id for maven packages that have low-confidence mappings
            # https://github.com/github/dependency-graph/issues/1755
            if object.package_manager == ::Types::PackageManager::MAVEN && !ALLOWED_MAVEN_MAPPING_CERTAINTIES.include?(object.package_github_repository_id_certainty)
              return nil
            end
          end

          object.package_github_repository_id
        end
      end

      # In a manifest dependencies have a label and a name
      # in pypi for instance, the name is the canonical package name
      # which a normalization is applied. The label, instead, is
      # what the user defined on their manifest file.

      # TO-DO remove when removing deprecated packageLabel in dotcom
      field :package_label, String, null: true

      field :package_name, String, null: true

      field :package_manager, Enums::PackageManager, null: true

      field :package_url, API::Types::ScalarURI, null: true

      def package_url
        # All graphql data passes through this method whether the data comes from DS-API, DGP, or DG-API.
        # When coming from DG-API, object is an instance of ManifestEntry which responds to `:manifest` and
        # `:repository_id`.  The creation of PackageUrl here fulfills the creation of package_url for DG-API.
        #
        # When coming from DGP, object is an instance of DependencyGraph::ObjectModel::DGPGraphqlDependency.
        # When coming from DS-API, object is an instance of DependencyGraph::ObjectModel::DSGraphqlDependency.
        # Neither of these classes respond to `:package_url` or `:repository_id`.  Both these classes have
        # access to the feature flag's value and will correctly return `nil` if the feature flag is disabled.
        #
        # For this reason, we need to check if the object responds to `:package_url` first and return the
        # value of `object.package_url` if it does.  If the value of `package_url` is not returned, it will
        # not be available to DGP and DS-API objects and package_url will always be `nil`.
        return object.package_url if object.respond_to?(:package_url)
        return nil unless object.manifest.ds_arbitrary_ecosystem_enabled?(object.github_repository_id)
        purl = PackageUrls::PackageUrl.from_package_release(
          package_manager: object.package_manager.human_name.downcase,
          name: object.package_name,
          version: requirement_set.exact_version).to_purl
        ScalarURI.coerce_isolated_input(purl)
      end

      field :package_id, ID, null: true

      def package_id
        package_id = if object.respond_to?(:package_id)
                       object.package_id
                     else
                       object.package.id
                     end
        GraphQL::Schema::UniqueWithinType.encode(Types::Package.graphql_name, package_id)
      end

      field :requirements, String, null: true

      field :scope, API::Enums::DependencyScope, null: true

      field :relationship, API::Enums::Relationship, null: true

      def relationship
        object.respond_to?(:relationship) ? object.relationship : nil
      end

      field :has_dependencies, Boolean, null: true

      def has_dependencies
        object.has_dependencies?
      end

      field :vulnerable_version_ranges, Connections::VulnerableVersionRangesConnection, max_page_size: nil, null: true

      def vulnerable_version_ranges
        if object.respond_to?(:vulnerable_version_ranges)
          object.vulnerable_version_ranges
        else
          []
        end
      end

      field :license, String, null: true

      private

      def normalize_requirements(requirements)
        case object.package_manager
        when ::Types::PackageManager::NPM
          ManifestAdapters::Npm::Requirements.new(requirements).normalize
        else
          # TODO: (elr) Do other package managers need normalizing?
          requirements
        end
      end

      def requirement_set
        valid = true
        requirement_set = Versioning::RequirementSet.deserialize(
          normalize_requirements(object.requirements),
          allow_named_versions: ::Types::PackageManager.allows_named_versions?(object.package_manager),
          on_error: ->(range) {
            log_invalid_range(range)
            valid = false
          },
        )
        valid ? requirement_set : Versioning::RequirementSet.wildcard
      end
    end
  end
end
