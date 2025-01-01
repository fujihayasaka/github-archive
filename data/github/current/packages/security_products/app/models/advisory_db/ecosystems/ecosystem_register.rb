# typed: strict
# frozen_string_literal: true

module AdvisoryDB
  module Ecosystems
    # A registry of known ecosystems
    class EcosystemRegister < AbstractEcosystemRegister
      extend T::Helpers
      extend T::Sig
      final!

      # Our private registry for ecosystems
      class Registry < AbstractEcosystemRegistry
        extend T::Helpers
        final!
      end
      private_constant :Registry

      sig(:final) { override.returns(Registry) }
      private_class_method def self.registry
        Registry.instance
      end

      # NOTE: When a new ecosystem becomes publically available, ensure the enum
      # is added to our REST API as well in
      # app/api/description/components/schemas/repository-advisory-ecosystems.yaml

      add(:RUBYGEMS, EcosystemV2.new(
        dependency_graph_supported: true,
        description: "Ruby gems hosted at RubyGems.org",
        hydro_enum_value: :RUBYGEMS,
        is_public: true,
        label: "RubyGems",
        name: "RubyGems",
        purl_type: "gem",
      ).freeze)
      add(:NPM, EcosystemV2.new(
        dependency_graph_supported: true,
        description: "JavaScript packages hosted at npmjs.com",
        hydro_enum_value: :NPM,
        is_public: true,
        label: "npm",
        name: "npm",
        purl_type: "npm",
      ).freeze)
      add(:PIP, EcosystemV2.new(
        dependency_graph_supported: true,
        description: "Python packages hosted at PyPI.org",
        hydro_enum_value: :PIP,
        is_public: true,
        label: "pip",
        name: "pip",
        purl_type: "pypi",
      ).freeze)
      add(:MAVEN, EcosystemV2.new(
        dependency_graph_supported: true,
        description: "Java artifacts hosted at the Maven central repository",
        hydro_enum_value: :MAVEN,
        is_public: true,
        label: "Maven",
        name: "maven",
        purl_type: "maven",
      ).freeze)
      add(:NUGET, EcosystemV2.new(
        dependency_graph_supported: true,
        description: ".NET packages hosted at the NuGet Gallery",
        hydro_enum_value: :NUGET,
        is_public: true,
        label: "NuGet",
        name: "nuget",
        purl_type: "nuget",
      ).freeze)
      add(:COMPOSER, EcosystemV2.new(
        dependency_graph_supported: true,
        description: "PHP packages hosted at packagist.org",
        hydro_enum_value: :COMPOSER,
        is_public: true,
        label: "Composer",
        name: "composer",
        purl_type: "composer",
      ).freeze)
      add(:GO, EcosystemV2.new(
        dependency_graph_supported: true,
        description: "Go modules",
        hydro_enum_value: :GO,
        is_public: true,
        label: "Go",
        name: "go",
        purl_type: "golang",
      ).freeze)
      add(:RUST, EcosystemV2.new(
        dependency_graph_supported: true,
        description: "Rust crates",
        hydro_enum_value: :RUST,
        is_public: true,
        label: "Rust",
        name: "rust",
        purl_type: "cargo",
      ).freeze)
      add(:ERLANG, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "Erlang/Elixir packages hosted at hex.pm",
        hydro_enum_value: :ERLANG,
        is_public: true,
        label: "Erlang",
        name: "erlang",
        purl_type: "hex",
      ).freeze)
      add(:ACTIONS, EcosystemV2.new(
        dependency_graph_supported: true,
        description: "GitHub Actions",
        hydro_enum_value: :ACTIONS,
        is_public: true,
        label: "GitHub Actions",
        name: "actions",
        # "githubactions" PURL type is provisional and may be subject to change
        purl_type: "githubactions",
      ).freeze)
      add(:PUB, EcosystemV2.new(
        dependency_graph_supported: true,
        description: "Dart packages hosted at pub.dev",
        hydro_enum_value: :PUB,
        is_public: true,
        label: "Pub",
        name: "pub",
        purl_type: "pub",
      ).freeze)
      add(:SWIFT, EcosystemV2.new(
        dependency_graph_supported: true,
        description: "Swift packages",
        hydro_enum_value: :SWIFT,
        is_public: true,
        label: "Swift",
        name: "swift",
        purl_type: "swift",
      ).freeze)

      # Ecosystems still in preview. These are hidden from the public and do not
      # generate Dependabot alerts/updates.
      add(:OTHER, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "Applications, runtimes, operating systems and other kinds of software",
        hydro_enum_value: :OTHER,
        is_public: false,
        label: "Other",
        name: "other",
        purl_type: "generic",
      ).freeze)

      # A dummy ecosystem that can use to test the non-public ecosystems
      add(:TEST_PREVIEW_ECO, EcosystemV2.new(
        dependency_graph_supported: false,
        description: "a non-public ecosystem for testing",
        hydro_enum_value: :TEST_PREVIEW_ECO,
        is_public: false,
        label: nil,
        name: "test_preview_eco",
        purl_type: nil,
      ).freeze)
    end
  end
end
