# typed: strict
# frozen_string_literal: true

module AdvisoryDB
  module EcosystemsV2
    extend T::Sig

    # The list of ecosystems that are supported in dotcom in some form or
    # another. All other lists below are expected to be a subset of this.
    SUPPORTED = T.let(AdvisoryDB::Ecosystems::EcosystemRegister.ecosystems.freeze, T::Array[AdvisoryDB::Ecosystems::EcosystemV2])
    private_constant :SUPPORTED

    SUPPORTED_NAMES = T.let(SUPPORTED.collect(&:name).freeze, T::Array[String])
    private_constant :SUPPORTED_NAMES

    # Inverse index of ecosystems by name
    SUPPORTED_BY_NAMES = T.let(
      SUPPORTED.each.with_object({}) do |ecosystem, memo|
        memo[ecosystem.name] = ecosystem
      end.freeze,
      T::Hash[String, AdvisoryDB::Ecosystems::EcosystemV2]
    )
    private_constant :SUPPORTED_BY_NAMES

    # Inverse index of ecosystems by label
    SUPPORTED_BY_LABELS = T.let(
      SUPPORTED.each.with_object({}) do |ecosystem, memo|
        memo[ecosystem.label] = ecosystem
      end.freeze,
      T::Hash[String, AdvisoryDB::Ecosystems::EcosystemV2]
    )
    private_constant :SUPPORTED_BY_LABELS

    # Inverse index of ecosystems by their Hydro enum value
    SUPPORTED_BY_HYDRO_ENUM_VALUES = T.let(
      SUPPORTED.each.with_object({}) do |ecosystem, memo|
        memo[ecosystem.hydro_enum_value] = ecosystem
      end.freeze,
      T::Hash[Symbol, AdvisoryDB::Ecosystems::EcosystemV2]
    )
    private_constant :SUPPORTED_BY_HYDRO_ENUM_VALUES

    # The subset of SUPPORTED that are public
    PUBLIC = T.let(SUPPORTED.select(&:public?).freeze, T::Array[AdvisoryDB::Ecosystems::EcosystemV2])
    private_constant :PUBLIC

    PUBLIC_NAMES = T.let(PUBLIC.collect(&:name).freeze, T::Array[String])
    private_constant :PUBLIC_NAMES

    PUBLIC_LABELS = T.let(PUBLIC.collect(&:label).freeze, T::Array[String])
    private_constant :PUBLIC_LABELS

    # The subset of SUPPORTED that are supported valid ecosystem in Dependency
    # Graph. See also `Dependabot::SECURITY_UPDATES_SUPPORTED`
    DEPENDENCY_GRAPH_SUPPORTED = T.let(SUPPORTED.select(&:dependency_graph_supported?), T::Array[AdvisoryDB::Ecosystems::EcosystemV2])
    private_constant :DEPENDENCY_GRAPH_SUPPORTED

    DEPENDENCY_GRAPH_SUPPORTED_NAMES = T.let(DEPENDENCY_GRAPH_SUPPORTED.collect(&:name).freeze, T::Array[String])
    private_constant :DEPENDENCY_GRAPH_SUPPORTED_NAMES

    DEPENDENCY_GRAPH_SUPPORTED_LABELS = T.let(DEPENDENCY_GRAPH_SUPPORTED.collect(&:label).freeze, T::Array[String])
    private_constant :DEPENDENCY_GRAPH_SUPPORTED_LABELS

    # TEMPORARY: PURL type ecosystems. These are kept separate from
    # SUPPORTED so that we can use a feature flag to control rollout, but
    # they can eventually be combined.
    SUPPORTED_PURL_TYPES = T.let(AdvisoryDB::Ecosystems::PurlTypeRegister.ecosystems.freeze, T::Array[AdvisoryDB::Ecosystems::EcosystemV2])
    SUPPORTED_PURL_TYPES_NAMES = T.let(SUPPORTED_PURL_TYPES.collect(&:name).freeze, T::Array[String])
    SUPPORTED_PURL_TYPES_BY_NAMES = T.let(
      SUPPORTED_PURL_TYPES.each.with_object({}) do |ecosystem, memo|
        memo[ecosystem.name] = ecosystem
      end.freeze,
      T::Hash[String, AdvisoryDB::Ecosystems::EcosystemV2]
    )
    SUPPORTED_PURL_TYPES_BY_LABELS = T.let(
      SUPPORTED_PURL_TYPES.each.with_object({}) do |ecosystem, memo|
        memo[ecosystem.label] = ecosystem
      end.freeze,
      T::Hash[String, AdvisoryDB::Ecosystems::EcosystemV2]
    )
    SUPPORTED_PURL_TYPES_BY_HYDRO_ENUM_VALUES = T.let(
      SUPPORTED_PURL_TYPES.each.with_object({}) do |ecosystem, memo|
        memo[ecosystem.hydro_enum_value] = ecosystem
      end.freeze,
      T::Hash[Symbol, AdvisoryDB::Ecosystems::EcosystemV2]
    )
    PUBLIC_PURL_TYPES = T.let(SUPPORTED_PURL_TYPES.select(&:public?).freeze, T::Array[AdvisoryDB::Ecosystems::EcosystemV2])
    PUBLIC_PURL_TYPES_NAMES = T.let(PUBLIC_PURL_TYPES.collect(&:name).freeze, T::Array[String])
    PUBLIC_PURL_TYPES_LABELS = T.let(PUBLIC_PURL_TYPES.collect(&:label).freeze, T::Array[String])

    # The list of all known ecosystems
    sig do
      params(
        include_purl_ecosystems: T::Boolean # TEMPORARY
      ).returns(T::Array[AdvisoryDB::Ecosystems::EcosystemV2])
    end
    def self.supported(include_purl_ecosystems: false)
      if include_purl_ecosystems
        (SUPPORTED + SUPPORTED_PURL_TYPES).freeze
      else
        SUPPORTED
      end
    end

    # A list of supported ecosystems names
    sig do
      params(
        include_purl_ecosystems: T::Boolean # TEMPORARY
      ).returns(T::Array[String])
    end
    def self.supported_names(include_purl_ecosystems: false)
      if include_purl_ecosystems
        (SUPPORTED_NAMES + SUPPORTED_PURL_TYPES_NAMES).freeze
      else
        SUPPORTED_NAMES
      end
    end
    class << self
      # A list of ecosystems permitted in the database by ::Vulnerability
      alias :database_enum :supported_names
    end

    # A list of public ecosystems
    #
    # Beware, this is overriding the built-in `public` method.
    # Example of what can go wrong: https://github.com/github/dependency-graph-api/pull/2557
    sig do
      params(
        include_purl_ecosystems: T::Boolean # TEMPORARY
      ).returns(T::Array[AdvisoryDB::Ecosystems::EcosystemV2])
    end
    def self.public(include_purl_ecosystems: false)
      if include_purl_ecosystems
        (PUBLIC + PUBLIC_PURL_TYPES).freeze
      else
        PUBLIC
      end
    end

    # A list of public ecosystems names
    sig do
      params(
        include_purl_ecosystems: T::Boolean # TEMPORARY
      ).returns(T::Array[String])
    end
    def self.public_names(include_purl_ecosystems: false)
      if include_purl_ecosystems
        (PUBLIC_NAMES + PUBLIC_PURL_TYPES_NAMES).freeze
      else
        PUBLIC_NAMES
      end
    end
    class << self
      # A list of ecosystems readable via ::SecurityAdvisory for our integrations
      alias :api_filter :public_names
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

    # A list of ecosystem names supported by dependency graph
    sig { returns(T::Array[String]) }
    def self.dependency_graph_supported_names
      DEPENDENCY_GRAPH_SUPPORTED_NAMES
    end

    # A list of ecosystems supported by dependency graph
    sig { returns(T::Array[AdvisoryDB::Ecosystems::EcosystemV2]) }
    def self.dependency_graph_supported
      DEPENDENCY_GRAPH_SUPPORTED
    end

    # Fetch an ecosystem from the registry by its slug
    sig do
      params(
        slug: Symbol
      ).returns(T.nilable(AdvisoryDB::Ecosystems::EcosystemV2))
    end
    def self.get(slug)
      # TEMPORARY: Include purl types always - if the system knows about one,
      # it should be able get the ecosystem
      AdvisoryDB::Ecosystems::EcosystemRegister.get(slug) || AdvisoryDB::Ecosystems::PurlTypeRegister.get(slug)
    end

    # Return an ecosystem given the name
    sig do
      params(
        name: String
      ).returns(T.nilable(AdvisoryDB::Ecosystems::EcosystemV2))
    end
    def self.by_name(name)
      ecosystems_by_name = SUPPORTED_BY_NAMES
      # TEMPORARY: Include purl types always - if the system knows about one,
      # it should be able get the ecosystem
      ecosystems_by_name = ecosystems_by_name.dup.reverse_merge(SUPPORTED_PURL_TYPES_BY_NAMES)
      ecosystems_by_name[name]
    end

    # Return an ecosystem given the label
    sig do
      params(
        label: String
      ).returns(T.nilable(AdvisoryDB::Ecosystems::EcosystemV2))
    end
    def self.by_label(label)
      ecosystems_by_label = SUPPORTED_BY_LABELS
      # TEMPORARY: Include purl types always - if the system knows about one,
      # it should be able get the ecosystem
      ecosystems_by_label = ecosystems_by_label.dup.reverse_merge(SUPPORTED_PURL_TYPES_BY_LABELS)
      ecosystems_by_label[label]
    end

    # Find the ecosystem matching a Hydro vulnerability ecosystem enum value
    sig do
      params(
        advisory_vulnerability: T::Hash[Symbol, T.untyped]
      ).returns(AdvisoryDB::Ecosystems::EcosystemV2)
    end
    def self.from_advisory_vulnerability(advisory_vulnerability)
      # TEMPORARY: Include purl types always - if the system knows about one,
      # it should be able get the ecosystem
      ecosystems_by_enums = T.let(
        SUPPORTED_BY_HYDRO_ENUM_VALUES.reverse_merge(SUPPORTED_PURL_TYPES_BY_HYDRO_ENUM_VALUES),
        T::Hash[Symbol, AdvisoryDB::Ecosystems::EcosystemV2]
      )
      platform = advisory_vulnerability[:package_ecosystem]
      T.must(ecosystems_by_enums[platform] || get(:OTHER))
    end

    # Return the label for an ecosystem given the name
    sig { params(name: String).returns(String) }
    def self.label(name)
      by_name(name)&.label || name
    end

    # Return the name of an ecosystem given the label
    sig { params(label: String).returns(String) }
    def self.name(label)
      by_label(label)&.name || label
    end

    # Return the PURL type for an ecosystem given the name
    sig { params(name: String).returns(String) }
    def self.purl_type(name)
      by_name(name)&.purl_type || name
    end
  end
end
