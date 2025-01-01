# typed: strict
# frozen_string_literal: true

module AdvisoryDB
  module Ecosystems
    extend T::Sig

    # Dictionary of our supported Ecosystems.
    #
    # Use `is_public: false` if an ecosystems is still in preview. This will
    # hide published advisories for that ecosystem. Hidden ecosystems should
    # not generate Dependabot alerts/updates!
    #
    # NOTE: When a new ecosystem becomes publically available, ensure the enum
    # is added to our REST API as well in
    # app/api/description/components/schemas/repository-advisory-ecosystems.yaml
    RUBYGEMS = T.let(Ecosystem.new(
      name: "RubyGems",
      description: "Ruby gems hosted at RubyGems.org",
      purl_type: "gem"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    NPM = T.let(Ecosystem.new(
      name: "npm",
      description: "JavaScript packages hosted at npmjs.com"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    PIP = T.let(Ecosystem.new(
      name: "pip",
      description: "Python packages hosted at PyPI.org",
      purl_type: "pypi"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    MAVEN = T.let(Ecosystem.new(
      name: "maven",
      label: "Maven",
      description: "Java artifacts hosted at the Maven central repository"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    NUGET = T.let(Ecosystem.new(
      name: "nuget",
      label: "NuGet",
      description: ".NET packages hosted at the NuGet Gallery"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    COMPOSER = T.let(Ecosystem.new(
      name: "composer",
      label: "Composer",
      description: "PHP packages hosted at packagist.org"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    GO = T.let(Ecosystem.new(
      name: "go",
      label: "Go",
      description: "Go modules",
      purl_type: "golang"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    RUST = T.let(Ecosystem.new(
      name: "rust",
      label: "Rust",
      description: "Rust crates",
      purl_type: "cargo"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    ERLANG = T.let(Ecosystem.new(
      name: "erlang",
      label: "Erlang",
      description: "Erlang/Elixir packages hosted at hex.pm",
      purl_type: "hex"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    ACTIONS = T.let(Ecosystem.new(
      name: "actions",
      label: "GitHub Actions",
      description: "GitHub Actions",
      # "githubactions" PURL type is provisional and may be subject to change
      purl_type: "githubactions"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    PUB = T.let(Ecosystem.new(
      name: "pub",
      label: "Pub",
      description: "Dart packages hosted at pub.dev"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    SWIFT = T.let(Ecosystem.new(
      name: "swift",
      label: "Swift",
      description: "Swift packages"
    ), AdvisoryDB::Ecosystems::Ecosystem)

    # Ecosystems still in preview. These are hidden from the public and do not
    # generate Dependabot alerts/updates.
    OTHER = T.let(Ecosystem.new(
      name: "other",
      label: "Other",
      description: "Applications, runtimes, operating systems and other kinds of software",
      is_public: false,
      purl_type: "generic"
    ), AdvisoryDB::Ecosystems::Ecosystem)

    # PURL ecosystems that are in preview. These are available to select on
    # repo advisories, but not on the global advisory improvement form. They do
    # not generate Dependabot alerts/updates.
    #
    # Note that these all set `is_public: true` even though they are still in
    # preview. This is because their inclusion in accessor method returns is
    # still controlled via the include_purl_ecosystems argument. As long as
    # that is false, these remain in preview mode.
    ALPM = T.let(Ecosystem.new(
      name: "alpm",
      label: "ALPM",
      description: "Arch Linux packages managed via libalpm/pacman",
      is_public: true # See note above
    ), AdvisoryDB::Ecosystems::Ecosystem)
    APK = T.let(Ecosystem.new(
      name: "apk",
      label: "APK",
      description: "APK-based packages",
      is_public: true # See note above
    ), AdvisoryDB::Ecosystems::Ecosystem)
    BITBUCKET = T.let(Ecosystem.new(
      name: "bitbucket_repository",
      label: "Bitbucket Repository",
      description: "Bitbucket-based projects hosted on bitbucket.org",
      is_public: true, # See note above
      purl_type: "bitbucket"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    COCOAPODS = T.let(Ecosystem.new(
      name: "cocoapods",
      label: "CocoaPods",
      description: "CocoaPod packages hosted at cocoapods.org",
      is_public: true # See note above
    ), AdvisoryDB::Ecosystems::Ecosystem)
    CONAN = T.let(Ecosystem.new(
      name: "conan_center",
      label: "Conan Center",
      description: "Conan C/C++ packages hosted at the Conan Center",
      is_public: true, # See note above
      purl_type: "conan"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    CONDA = T.let(Ecosystem.new(
      name: "conda_forge",
      label: "Conda Forge",
      description: "Conda packages hosted at the conda-forge",
      is_public: true, # See note above
      purl_type: "conda"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    CRAN = T.let(Ecosystem.new(
      name: "cran",
      label: "CRAN",
      description: "CRAN R packages hosted at cran.r-project.org",
      is_public: true # See note above
    ), AdvisoryDB::Ecosystems::Ecosystem)
    DEB = T.let(Ecosystem.new(
      name: "deb",
      description: "Debian, Debian derivatives, and Ubuntu packages",
      is_public: true # See note above
    ), AdvisoryDB::Ecosystems::Ecosystem)
    DOCKER = T.let(Ecosystem.new(
      name: "docker_hub",
      label: "Docker Hub",
      description: "Docker images hosted at hub.docker.com",
      is_public: true, # See note above
      purl_type: "docker"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    GENERIC = T.let(Ecosystem.new(
      name: "generic",
      label: "Generic",
      description: "Plain, generic packages that do not fit anywhere else",
      is_public: true # See note above
    ), AdvisoryDB::Ecosystems::Ecosystem)
    GITHUB = T.let(Ecosystem.new(
      name: "github_repository",
      label: "GitHub Repository",
      description: "Github-based projects hosted at github.com",
      is_public: true, # See note above
      purl_type: "github"
    ), AdvisoryDB::Ecosystems::Ecosystem)
    HACKAGE = T.let(Ecosystem.new(
      name: "hackage",
      description: "Haskel packages hosted at hackage.haskell.org",
      is_public: true # See note above
    ), AdvisoryDB::Ecosystems::Ecosystem)
    HUGGINGFACE = T.let(Ecosystem.new(
      name: "huggingface",
      label: "Hugging Face",
      description: "Hugging Face ML models hosted at huggingface.co",
      is_public: true # See note above
    ), AdvisoryDB::Ecosystems::Ecosystem)
    MLFLOW = T.let(Ecosystem.new(
      name: "mlflow",
      label: "MLflow",
      description: "MLflow ML models (Azure ML, Databricks, etc.)",
      is_public: true # See note above
    ), AdvisoryDB::Ecosystems::Ecosystem)
    QPKG = T.let(Ecosystem.new(
      name: "qpkg",
      label: "QPKG",
      description: "QNX packages",
      is_public: true # See note above
    ), AdvisoryDB::Ecosystems::Ecosystem)
    OCI = T.let(Ecosystem.new(
      name: "oci",
      label: "OCI Artifact",
      description: "Artifacts stored in registries that conform to the OCI Distribution Specification",
      is_public: true # See note above
    ), AdvisoryDB::Ecosystems::Ecosystem)
    RPM = T.let(Ecosystem.new(
      name: "rpm",
      label: "RPM",
      description: "RPM-based packages for Red Hat, Fedora, CentOS, openSUSE, etc.",
      is_public: true # See note above
    ), AdvisoryDB::Ecosystems::Ecosystem)
    SWID = T.let(Ecosystem.new(
      name: "swid",
      label: "SWID",
      description: "Packages using ISO-IEC 19770-2 Software Identification (SWID) tags",
      is_public: true # See note above
    ), AdvisoryDB::Ecosystems::Ecosystem)

    # A dummy ecosystem that can use to test the non-public ecosystems
    TEST_PREVIEW_ECO = T.let(Ecosystem.new(
      name: "test_preview_eco",
      description: "a non-public ecosystem for testing",
      is_public: false
    ), AdvisoryDB::Ecosystems::Ecosystem)

    # The list of ecosystems that are supported in dotcom in some form or
    # another. As more ecosystems are supported, they must be added to the list
    # below. All other lists below are expected to be a subset of this.
    #
    # Order is not important, so please keep alphabetized.
    SUPPORTED = T.let([
      COMPOSER,
      ERLANG,
      ACTIONS,
      GO,
      MAVEN,
      NPM,
      NUGET,
      PIP,
      PUB,
      RUBYGEMS,
      RUST,
      SWIFT,
      OTHER,
      TEST_PREVIEW_ECO,
    ].freeze, T::Array[AdvisoryDB::Ecosystems::Ecosystem])
    private_constant :SUPPORTED

    # The subset of ECOSYSTEMS that are supported valid ecosystem in Dependency
    # Graph. See also `Dependabot::SECURITY_UPDATES_SUPPORTED`
    #
    # Order is not important, so please keep alphabetized.
    DEPENDENCY_GRAPH_SUPPORTED = T.let([
      RUBYGEMS,
      NPM,
      PIP,
      MAVEN,
      NUGET,
      COMPOSER,
      GO,
      ACTIONS,
      RUST,
      PUB,
      SWIFT,
    ].freeze, T::Array[AdvisoryDB::Ecosystems::Ecosystem])
    private_constant :DEPENDENCY_GRAPH_SUPPORTED

    # The subset of ECOSYSTEMS that appear in Hydro vulnerability payloads.
    # Note that these are symbols, not constants. It's currently assumed that
    # the symbol matches the Ecosystem enum from the hydro message which
    # matches the name of the ecosystem constant defined above.
    #
    # See lib/hydro/schemas/advisory_db/v0/entities/vulnerability_pb.rb
    #
    # Order is not important, so please keep in sync with the hydro enum
    INTERNAL_ADVISORY_DB_SCHEMA_ECOSYSTEM_TYPES = T.let(%i[
      RUBYGEMS
      NPM
      PIP
      MAVEN
      NUGET
      COMPOSER
      GO
      RUST
      ERLANG
      SWIFT
      OTHER
      ACTIONS
      PUB
    ].freeze, T::Array[Symbol])
    private_constant :INTERNAL_ADVISORY_DB_SCHEMA_ECOSYSTEM_TYPES

    SUPPORTED_NAMES = T.let(SUPPORTED.collect(&:name).freeze, T::Array[String])
    private_constant :SUPPORTED_NAMES

    DEPENDENCY_GRAPH_SUPPORTED_NAMES = T.let(DEPENDENCY_GRAPH_SUPPORTED.collect(&:name).freeze, T::Array[String])
    private_constant :DEPENDENCY_GRAPH_SUPPORTED_NAMES

    DEPENDENCY_GRAPH_SUPPORTED_LABELS = T.let(DEPENDENCY_GRAPH_SUPPORTED.collect(&:label).freeze, T::Array[String])
    private_constant :DEPENDENCY_GRAPH_SUPPORTED_LABELS

    PUBLIC = T.let(SUPPORTED.select(&:public?).freeze, T::Array[AdvisoryDB::Ecosystems::Ecosystem])
    private_constant :PUBLIC

    PUBLIC_NAMES = T.let(PUBLIC.collect(&:name).freeze, T::Array[String])
    private_constant :PUBLIC_NAMES

    PUBLIC_LABELS = T.let(PUBLIC.collect(&:label).freeze, T::Array[String])
    private_constant :PUBLIC_LABELS

    # TEMPORARY: PURL type ecosystems. These are kept separate from
    # SUPPORTED so that we can use a feature flag to control rollout, but
    # they can eventually be combined.
    SUPPORTED_PURL_TYPES = T.let([
      ALPM,
      APK,
      BITBUCKET,
      COCOAPODS,
      CONAN,
      CONDA,
      CRAN,
      DEB,
      DOCKER,
      GENERIC,
      GITHUB,
      HACKAGE,
      HUGGINGFACE,
      MLFLOW,
      QPKG,
      OCI,
      RPM,
      SWID,
    ].freeze, T::Array[AdvisoryDB::Ecosystems::Ecosystem])
    private_constant :SUPPORTED_PURL_TYPES

    # TEMPORARY: PURL type ecosystems that appear in Hydro vulnerability
    # payloads. These are kept separate from
    # INTERNAL_ADVISORY_DB_SCHEMA_ECOSYSTEM_TYPES so that we can use a
    # feature flag to control rollout, but they can eventually be combined.
    # Note that these are symbols, not constants.
    #
    # See lib/hydro/schemas/advisory_db/v0/entities/vulnerability_pb.rb
    INTERNAL_ADVISORY_DB_SCHEMA_PURL_ECOSYSTEM_TYPES = T.let(%i[
      ALPM
      APK
      BITBUCKET
      COCOAPODS
      CONAN
      CONDA
      CRAN
      DEB
      DOCKER
      GENERIC
      GITHUB
      HACKAGE
      HUGGINGFACE
      MLFLOW
      QPKG
      OCI
      RPM
      SWID
    ].freeze, T::Array[Symbol])
    private_constant :INTERNAL_ADVISORY_DB_SCHEMA_PURL_ECOSYSTEM_TYPES

    # TEMPORARY
    SUPPORTED_PURL_TYPES_NAMES = T.let(SUPPORTED_PURL_TYPES.collect(&:name).freeze, T::Array[String])
    private_constant :SUPPORTED_PURL_TYPES_NAMES

    # TEMPORARY
    PUBLIC_PURL_TYPES = T.let(SUPPORTED_PURL_TYPES.select(&:public?).freeze, T::Array[AdvisoryDB::Ecosystems::Ecosystem])
    private_constant :PUBLIC_PURL_TYPES

    # TEMPORARY
    PUBLIC_PURL_TYPES_NAMES = T.let(PUBLIC_PURL_TYPES.collect(&:name).freeze, T::Array[String])
    private_constant :PUBLIC_PURL_TYPES_NAMES

    # TEMPORARY
    PUBLIC_PURL_TYPES_LABELS = T.let(PUBLIC_PURL_TYPES.collect(&:label).freeze, T::Array[String])
    private_constant :PUBLIC_PURL_TYPES_LABELS

    # A list of supported ecosystems
    #
    # Beware, this is overriding the built-in `public` method.
    # Example of what can go wrong: https://github.com/github/dependency-graph-api/pull/2557
    sig do
      params(
        include_purl_ecosystems: T::Boolean # TEMPORARY
      ).returns(T::Array[AdvisoryDB::Ecosystems::Ecosystem])
    end
    def self.supported(include_purl_ecosystems: false)
      if include_purl_ecosystems
        (SUPPORTED + SUPPORTED_PURL_TYPES).freeze
      else
        SUPPORTED
      end
    end

    # A list of public ecosystems
    #
    # Beware, this is overriding the built-in `public` method.
    # Example of what can go wrong: https://github.com/github/dependency-graph-api/pull/2557
    sig do
      params(
        include_purl_ecosystems: T::Boolean # TEMPORARY
      ).returns(T::Array[AdvisoryDB::Ecosystems::Ecosystem])
    end
    def self.public(include_purl_ecosystems: false)
      if include_purl_ecosystems
        (PUBLIC + PUBLIC_PURL_TYPES).freeze
      else
        PUBLIC
      end
    end

    # A list of ecosystems readable via ::SecurityAdvisory for our integrations
    sig do
      params(
        include_purl_ecosystems: T::Boolean # TEMPORARY
      ).returns(T::Array[String])
    end
    def self.api_filter(include_purl_ecosystems: false)
      if include_purl_ecosystems
        (PUBLIC_NAMES + PUBLIC_PURL_TYPES_NAMES).freeze
      else
        PUBLIC_NAMES
      end
    end
    class << self
      # A list of public ecosystems names
      alias :public_names :api_filter
    end

    # A list of public ecosystems labels
    sig do
      params(
        include_purl_ecosystems: T::Boolean # TEMPORARY
      ).returns(T::Array[String])
    end
    def self.public_labels(include_purl_ecosystems: false)
      if include_purl_ecosystems
        (PUBLIC_LABELS + PUBLIC_PURL_TYPES_LABELS).freeze
      else
        PUBLIC_LABELS
      end
    end

    # A list of ecosystems permitted in the database by ::Vulnerability
    sig do
      params(
        include_purl_ecosystems: T::Boolean # TEMPORARY
      ).returns(T::Array[String])
    end
    def self.database_enum(include_purl_ecosystems: false)
      if include_purl_ecosystems
        (SUPPORTED_NAMES + SUPPORTED_PURL_TYPES_NAMES).freeze
      else
        SUPPORTED_NAMES
      end
    end
    class << self
      # A list of supported ecosystems names
      alias :supported_names :database_enum
    end

    # A list of internal ecosystem types that appear in Hydro vulnerability payloads
    sig do
      params(
        include_purl_ecosystems: T::Boolean # TEMPORARY
      ).returns(T::Array[Symbol])
    end
    def self.internal_ecosystem_types(include_purl_ecosystems: false)
      if include_purl_ecosystems
        (INTERNAL_ADVISORY_DB_SCHEMA_ECOSYSTEM_TYPES + INTERNAL_ADVISORY_DB_SCHEMA_PURL_ECOSYSTEM_TYPES).freeze
      else
        INTERNAL_ADVISORY_DB_SCHEMA_ECOSYSTEM_TYPES
      end
    end

    # A list of ecosystem names supported by dependency graph
    sig { returns(T::Array[String]) }
    def self.dependency_graph_supported_names
      DEPENDENCY_GRAPH_SUPPORTED_NAMES
    end

    # A list of ecosystems supported by dependency graph
    sig { returns(T::Array[AdvisoryDB::Ecosystems::Ecosystem]) }
    def self.dependency_graph_supported
      DEPENDENCY_GRAPH_SUPPORTED
    end

    # Find the ecosystem matching a Hydro vulnerability ecosystem enum value
    sig do
      params(
        advisory_vulnerability: T::Hash[Symbol, T.untyped],
        include_purl_ecosystems: T::Boolean # TEMPORARY
      ).returns(AdvisoryDB::Ecosystems::Ecosystem)
    end
    def self.from_advisory_vulnerability(advisory_vulnerability, include_purl_ecosystems: false)
      ecosystem_types = internal_ecosystem_types(include_purl_ecosystems: include_purl_ecosystems)
      platform = advisory_vulnerability[:package_ecosystem]
      return OTHER unless ecosystem_types.include?(platform)
      const_get(platform)
    end

    # Return the label for an ecosystem given the name
    sig do
      params(
        name: String,
        include_purl_ecosystems: T::Boolean # TEMPORARY
      ).returns(String)
    end
    def self.label(name, include_purl_ecosystems: false)
      ecosystems = supported
      ecosystems += SUPPORTED_PURL_TYPES if include_purl_ecosystems
      ecosystems.detect { |ecosystem| ecosystem.name == name }&.label || name
    end

    # Return the name of an ecosystem given the label
    sig do
      params(
        label: String,
        include_purl_ecosystems: T::Boolean # TEMPORARY
      ).returns(String)
    end
    def self.name(label, include_purl_ecosystems: false)
      ecosystems = supported
      ecosystems += SUPPORTED_PURL_TYPES if include_purl_ecosystems
      ecosystems.detect { |ecosystem| ecosystem.label == label }&.name || label
    end

    # Return the PURL type for an ecosystem given the name
    sig do
      params(
        name: String,
        include_purl_ecosystems: T::Boolean # TEMPORARY
      ).returns(String)
    end
    def self.purl_type(name, include_purl_ecosystems: false)
      ecosystems = supported
      ecosystems += SUPPORTED_PURL_TYPES if include_purl_ecosystems
      ecosystems.detect { |ecosystem| ecosystem.name == name }&.purl_type || name
    end
  end
end
