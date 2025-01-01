# typed: strict
# frozen_string_literal: true

module AdvisoryDB
  module Ecosystems
    # TEMPORARY: A registry of purl type ecosystems. These are kept separate
    # from Register so that we can use a feature flag to control rollout, but
    # they can eventually be combined. They do not generate Dependabot alerts/
    # updates.
    class PurlTypeRegister < AbstractEcosystemRegister
      extend T::Helpers
      extend T::Sig
      final!

      # Our private registry for purl type ecosystems
      class Registry < AbstractEcosystemRegistry
        extend T::Helpers
        final!
      end
      private_constant :Registry

      sig(:final) { override.returns(Registry) }
      private_class_method def self.registry
        Registry.instance
      end

      # Note that these all set `is_public: true` even though they are still in
      # preview. This is because their inclusion in accessor method returns is
      # still controlled via the include_purl_ecosystems argument. As long as
      # that is false, these remain in preview mode.

      add(:ALPM, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "Arch Linux packages managed via libalpm/pacman",
        hydro_enum_value: :ALPM,
        is_public: true, # See note above
        label: "ALPM",
        name: "alpm",
        purl_type: "alpm",
      ).freeze)
      add(:APK, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "APK-based packages",
        hydro_enum_value: :APK,
        is_public: true, # See note above
        label: "APK",
        name: "apk",
        purl_type: "apk",
      ).freeze)
      add(:BITBUCKET, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "Bitbucket-based projects hosted on bitbucket.org",
        hydro_enum_value: :BITBUCKET,
        is_public: true, # See note above
        label: "Bitbucket Repository",
        name: "bitbucket_repository",
        purl_type: "bitbucket",
      ).freeze)
      add(:COCOAPODS, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "CocoaPod packages hosted at cocoapods.org",
        hydro_enum_value: :COCOAPODS,
        is_public: true, # See note above
        label: "CocoaPods",
        name: "cocoapods",
        purl_type: "cocoapods",
      ).freeze)
      add(:CONAN, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "Conan C/C++ packages hosted at the Conan Center",
        hydro_enum_value: :CONAN,
        is_public: true, # See note above
        label: "Conan Center",
        name: "conan_center",
        purl_type: "conan",
      ).freeze)
      add(:CONDA, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "Conda packages hosted at the conda-forge",
        hydro_enum_value: :CONDA,
        is_public: true, # See note above
        label: "Conda Forge",
        name: "conda_forge",
        purl_type: "conda",
      ).freeze)
      add(:CRAN, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "CRAN R packages hosted at cran.r-project.org",
        hydro_enum_value: :CRAN,
        is_public: true, # See note above
        label: "CRAN",
        name: "cran",
        purl_type: "cran",
      ).freeze)
      add(:DEB, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "Debian, Debian derivatives, and Ubuntu packages",
        hydro_enum_value: :DEB,
        is_public: true, # See note above
        label: "deb",
        name: "deb",
        purl_type: "deb",
      ).freeze)
      add(:DOCKER, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "Docker images hosted at hub.docker.com",
        hydro_enum_value: :DOCKER,
        is_public: true, # See note above
        label: "Docker Hub",
        name: "docker_hub",
        purl_type: "docker",
      ).freeze)
      add(:GENERIC, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "Plain, generic packages that do not fit anywhere else",
        hydro_enum_value: :GENERIC,
        is_public: true, # See note above
        label: "Generic",
        name: "generic",
        purl_type: "generic",
      ).freeze)
      add(:GITHUB, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "Github-based projects hosted at github.com",
        hydro_enum_value: :GITHUB,
        is_public: true, # See note above
        label: "GitHub Repository",
        name: "github_repository",
        purl_type: "github",
      ).freeze)
      add(:HACKAGE, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "Haskel packages hosted at hackage.haskell.org",
        hydro_enum_value: :HACKAGE,
        is_public: true, # See note above
        label: "hackage",
        name: "hackage",
        purl_type: "hackage",
      ).freeze)
      add(:HUGGINGFACE, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "Hugging Face ML models hosted at huggingface.co",
        hydro_enum_value: :HUGGINGFACE,
        is_public: true, # See note above
        label: "Hugging Face",
        name: "huggingface",
        purl_type: "huggingface",
      ).freeze)
      add(:MLFLOW, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "MLflow ML models (Azure ML, Databricks, etc.)",
        hydro_enum_value: :MLFLOW,
        is_public: true, # See note above
        label: "MLflow",
        name: "mlflow",
        purl_type: "mlflow",
      ).freeze)
      add(:QPKG, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "QNX packages",
        hydro_enum_value: :QPKG,
        is_public: true, # See note above
        label: "QPKG",
        name: "qpkg",
        purl_type: "qpkg",
      ).freeze)
      add(:OCI, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "Artifacts stored in registries that conform to the OCI Distribution Specification",
        hydro_enum_value: :OCI,
        is_public: true, # See note above
        label: "OCI Artifact",
        name: "oci",
        purl_type: "oci",
      ).freeze)
      add(:RPM, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "RPM-based packages for Red Hat, Fedora, CentOS, openSUSE, etc.",
        hydro_enum_value: :RPM,
        is_public: true, # See note above
        label: "RPM",
        name: "rpm",
        purl_type: "rpm",
      ).freeze)
      add(:SWID, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "Packages using ISO-IEC 19770-2 Software Identification (SWID) tags",
        hydro_enum_value: :SWID,
        is_public: true, # See note above
        label: "SWID",
        name: "swid",
        purl_type: "swid",
      ).freeze)
    end
  end
end
