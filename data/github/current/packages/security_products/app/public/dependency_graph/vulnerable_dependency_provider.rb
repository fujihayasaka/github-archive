# typed: strict
# frozen_string_literal: true

# DependencyGraph::VulnerableDependencyProvider implements helpers to determine which service to use
# in Dependabot Alerting contexts.
#
# This module is used by the Dependency Graph domain as part of our effort to cut over from the legacy
# Dependency Graph API service to Dependency Graph Platform.
#
module DependencyGraph
  module VulnerableDependencyProvider
    DGP_BETA_DETECTIONS_FLAG = "dependency_graph_dgp_beta_advisory_alerting"
    DGP_NPM_FEATURE_FLAG = "dependency_graph_dgp_backed_npm_alerts"

    class Provider < T::Struct
      # A humanized service name suitable for logging or error messages
      prop :name, String

      # A short-hand representation suitable for use in metrics
      prop :slug, Symbol

      # The value used to represent this provider in Hydro protobufs
      prop :hydro_enum, Symbol

      # Ecosystems which are fully supported, including in GHES environments
      prop :ecosystems, T::Array[AdvisoryDB::Ecosystems::EcosystemV2], default: []

      # Ecosystems which are only supported if the target Repository has the corresponding feature flag enabled.
      #
      # NOTE: This is ignored in GHES environments.
      prop :beta_ecosystems, T::Hash[AdvisoryDB::Ecosystems::EcosystemV2, String], default: {}

      # Determines whether this provider is currently in beta for advisory detection, if this is true then
      # alerts will only be produced and processed if the DGP_BETA_DETECTIONS_FLAG is enabled globally for the
      # environment.
      #
      # NOTE: Beta detection providers will always be disabled in GHES.
      prop :beta_detection_provider, T::Boolean, default: false

      # Ecosystems which are end of life for this provider, they will be considered unsupported if the target
      # repository has the corresponding feature flag enabled.
      #
      # NOTE: This is ignored in GHES environments.
      prop :eol_ecosystems, T::Hash[AdvisoryDB::Ecosystems::EcosystemV2, String], default: {}

      sig { params(repository: Repository, vvr: VulnerableVersionRange).returns(T::Boolean) }
      def provides_data_for?(repository, vvr)
        ecosystem = T.must(ecosystem_from_database_name(T.must(vvr.ecosystem)))

        unless GitHub.enterprise?
          # We are not enabled if this repository is flagged as having deprecated this ecosystem for this provider
          if eol_ecosystems.keys.include?(ecosystem)
            return !DependencyGraph.check_feature_for_repo_or_owner(repository, eol_ecosystems[ecosystem])
          end

          # We are enabled if this repository is opted in for a beta ecosystem from this provider
          if beta_ecosystems.keys.include?(ecosystem)
            return DependencyGraph.check_feature_for_repo_or_owner(repository, beta_ecosystems[ecosystem])
          end
        end

        ecosystems.include?(ecosystem)
      end

      sig { returns(T::Boolean) }
      def process_detections?
        return true unless beta_detection_provider

        VulnerableDependencyProvider.process_beta_provider_detections?
      end

      sig { params(vvr: VulnerableVersionRange, include_beta_support: T::Boolean).returns(T::Boolean) }
      def provides_detections_for?(vvr, include_beta_support: false)
        ecosystem = T.must(ecosystem_from_database_name(T.must(vvr.ecosystem)))

        ecosystems.include?(ecosystem) || (include_beta_support && beta_ecosystems.include?(ecosystem))
      end

      sig { returns(Symbol) }
      def disabled_slug
        "#{slug.downcase}_provider_disabled".to_sym
      end

      private

      sig { params(db_name: String).returns(T.nilable(AdvisoryDB::Ecosystems::EcosystemV2)) }
      def ecosystem_from_database_name(db_name)
        DependencyGraph::Ecosystems::SUPPORTED.find do |ecosystem|
          ecosystem.name == db_name
        end
      end
    end

    # The legacy Dependency Graph service, supports any AdvisoryDB::Ecosystems::EcosystemV2 that has the
    # `dependency_graph_supported?` flag set to true
    DG_API = Provider.new(
      name: "Dependency Graph API",
      slug: :DG_API,
      hydro_enum: :DEPENDENCY_GRAPH_API,
      ecosystems: DependencyGraph::Ecosystems::SUPPORTED,
      eol_ecosystems: {
        T.must(AdvisoryDB::Ecosystems::EcosystemRegister.get(:NPM)) => DGP_NPM_FEATURE_FLAG
      }
    )

    # The replacement service which supports a subset of `DependencyGraph::Ecosystems::SUPPORTED` that will
    # we will iterated from beta to full support over time.
    DGP = Provider.new(
      name: "Dependency Graph Platform",
      slug: :DGP,
      hydro_enum: :DEPENDENCY_GRAPH_PLATFORM,
      beta_ecosystems: {
        T.must(AdvisoryDB::Ecosystems::EcosystemRegister.get(:NPM)) => DGP_NPM_FEATURE_FLAG
      },
      beta_detection_provider: true
    )

    sig { returns(T::Boolean) }
    def self.process_beta_provider_detections?
      return false if GitHub.enterprise?

      GitHub.flipper[DependencyGraph::VulnerableDependencyProvider::DGP_BETA_DETECTIONS_FLAG].enabled?
    end

    sig { params(hydro_enum: Symbol).returns(Provider) }
    def self.provider_from_hydro_enum(hydro_enum)
      return DGP if hydro_enum == DGP.hydro_enum

      DG_API
    end

    sig { params(vvr: VulnerableVersionRange, include_beta_support: T::Boolean).returns(T::Array[Provider]) }
    def self.providers_for(vvr, include_beta_support: false)
      return [DG_API] if GitHub.enterprise?

      [DG_API, DGP].select do |provider|
        provider.provides_detections_for?(vvr, include_beta_support:)
      end
    end

    sig { params(repository: Repository).returns(T::Boolean) }
    def self.updates_using_dgp?(repository)
      return false if GitHub.enterprise?

      repository.feature_enabled?(DependencyGraph::VulnerableDependencyProvider::DGP_NPM_FEATURE_FLAG)
    end
  end
end
