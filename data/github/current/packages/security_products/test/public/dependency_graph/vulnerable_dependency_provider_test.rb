# typed: true
# frozen_string_literal: true

require "test_helper"

class DependencyGraph::VulnerableDependencyProviderTest < GitHub::TestCase
  fixtures do
    @repository = create(:repository)
  end

  setup do
    @npm = AdvisoryDB::Ecosystems::EcosystemRegister.get(:NPM)
    @dg_api_only_ecosystems = DependencyGraph::Ecosystems::SUPPORTED - [@npm]

    # Creating a generic provider for some tests, Dave is very opinionated having
    # decided to drop golang support for rust and drop composer entirely.
    @provider = DependencyGraph::VulnerableDependencyProvider::Provider.new(
      name: "Dave's Discount Dependency Data",
      slug: :d4,
      hydro_enum: :DAVES_DISCOUNT_DEPENDENCY_DATA,
      ecosystems: [
        T.must(AdvisoryDB::Ecosystems::EcosystemRegister.get(:MAVEN)),
        T.must(AdvisoryDB::Ecosystems::EcosystemRegister.get(:COMPOSER))
      ],
      beta_ecosystems: {
        T.must(AdvisoryDB::Ecosystems::EcosystemRegister.get(:RUST)) => "rust_beta"
      },
      eol_ecosystems: {
        T.must(AdvisoryDB::Ecosystems::EcosystemRegister.get(:GO)) => "rust_beta",
        T.must(AdvisoryDB::Ecosystems::EcosystemRegister.get(:COMPOSER)) => "eol_composer"
      }
    )
  end

  context "::process_beta_provider_detections?" do
    test "it is enabled with the feature flag", feature_enabled: DependencyGraph::VulnerableDependencyProvider::DGP_BETA_DETECTIONS_FLAG, skip_enterprise: true do
      assert DependencyGraph::VulnerableDependencyProvider.process_beta_provider_detections?
    end

    test "it is disabled without the feature flag", feature_disabled: DependencyGraph::VulnerableDependencyProvider::DGP_BETA_DETECTIONS_FLAG, skip_enterprise: true do
      refute DependencyGraph::VulnerableDependencyProvider.process_beta_provider_detections?
    end

    test "it is disabled in enterprise", enterprise_only: true do
      refute DependencyGraph::VulnerableDependencyProvider.process_beta_provider_detections?
    end
  end

  context "::provider_from_hydro_enum" do
    test "it correctly identifies DGP the hydro value" do
      provider = DependencyGraph::VulnerableDependencyProvider.provider_from_hydro_enum(:DEPENDENCY_GRAPH_PLATFORM)

      assert_equal(provider, DependencyGraph::VulnerableDependencyProvider::DGP)
    end

    test "it correctly identifies DG-API the hydro value" do
      provider = DependencyGraph::VulnerableDependencyProvider.provider_from_hydro_enum(:DEPENDENCY_GRAPH_API)

      assert_equal(provider, DependencyGraph::VulnerableDependencyProvider::DG_API)
    end

    test "it delegates to DG-API for the unknown value" do
      provider = DependencyGraph::VulnerableDependencyProvider.provider_from_hydro_enum(:UNKNOWN_DEPENDENCY_PROVIDER)

      assert_equal(provider, DependencyGraph::VulnerableDependencyProvider::DG_API)
    end

    test "it tolerates garbage inputs, defaulting to DG-API" do
      provider = DependencyGraph::VulnerableDependencyProvider.provider_from_hydro_enum(:DAVES_DISCOUNT_DEPENDENCY_DATA)

      assert_equal(provider, DependencyGraph::VulnerableDependencyProvider::DG_API)
    end
  end

  context "::providers_for" do
    test "it returns only DG API for all supported ecosystems except npm", skip_enterprise: true do
      @dg_api_only_ecosystems.each do |ecosystem|
        @vulnerability = create(:published_vulnerability, ecosystem: ecosystem.name, with_ranges: 1)

        providers = DependencyGraph::VulnerableDependencyProvider.providers_for(
          @vulnerability.vulnerable_version_ranges.sole
        )

        assert_equal DependencyGraph::VulnerableDependencyProvider::DG_API, providers.sole
      end
    end

    test "it returns only DG API for npm by default", skip_enterprise: true do
      @vulnerability = create(:published_vulnerability, ecosystem: @npm.name, with_ranges: 1)

      providers = DependencyGraph::VulnerableDependencyProvider.providers_for(
        @vulnerability.vulnerable_version_ranges.sole
      )

      assert_equal DependencyGraph::VulnerableDependencyProvider::DG_API, providers.sole
    end

    test "it returns both DG API and DGP for npm when beta ecosystems are requested", skip_enterprise: true do
      @vulnerability = create(:published_vulnerability, ecosystem: @npm.name, with_ranges: 1)

      providers = DependencyGraph::VulnerableDependencyProvider.providers_for(
        @vulnerability.vulnerable_version_ranges.sole,
        include_beta_support: true,
      )

      assert_equal 2, providers.count
      assert_includes providers, DependencyGraph::VulnerableDependencyProvider::DG_API
      assert_includes providers, DependencyGraph::VulnerableDependencyProvider::DGP
    end

    test "it returns DG API in GHES environments for all supported ecosystems", enterprise_only: true do
      DependencyGraph::Ecosystems::SUPPORTED.each do |ecosystem|
        @vulnerability = create(:published_vulnerability, ecosystem: ecosystem.name, with_ranges: 1)

        providers = DependencyGraph::VulnerableDependencyProvider.providers_for(
          @vulnerability.vulnerable_version_ranges.sole
        )

        assert_equal DependencyGraph::VulnerableDependencyProvider::DG_API, providers.sole
      end
    end

    test "it ignores the beta ecosystem flag in GHES enviroments", enterprise_only: true do
      DependencyGraph::Ecosystems::SUPPORTED.each do |ecosystem|
        @vulnerability = create(:published_vulnerability, ecosystem: ecosystem.name, with_ranges: 1)

        providers = DependencyGraph::VulnerableDependencyProvider.providers_for(
          @vulnerability.vulnerable_version_ranges.sole,
          include_beta_support: true
        )

        assert_equal DependencyGraph::VulnerableDependencyProvider::DG_API, providers.sole
      end
    end
  end

  context "Generic Provider" do
    context "#provides_data_for?" do
      test "it is enabled for a fully supported ecosystem" do
        @vulnerability = create(:published_vulnerability, ecosystem: "maven", with_ranges: 1)

        assert @provider.provides_data_for?(@repository, @vulnerability.vulnerable_version_ranges.sole)
      end

      test "it is disabled for a beta ecosystem by default", skip_enterprise: true do
        @repository.disable_feature("rust_beta")
        @vulnerability = create(:published_vulnerability, ecosystem: "rust", with_ranges: 1)

        refute @provider.provides_data_for?(@repository, @vulnerability.vulnerable_version_ranges.sole)
      end

      test "it is enabled for a beta ecosystem when the repository has a feature flag enabled", skip_enterprise: true do
        @repository.enable_feature("rust_beta")
        @vulnerability = create(:published_vulnerability, ecosystem: "rust", with_ranges: 1)

        assert @provider.provides_data_for?(@repository, @vulnerability.vulnerable_version_ranges.sole)
      end

      test "it is enabled for a end of life ecosystem by default", skip_enterprise: true do
        @repository.disable_feature("rust_beta")
        @vulnerability = create(:published_vulnerability, ecosystem: "go", with_ranges: 1)

        assert @provider.provides_data_for?(@repository, @vulnerability.vulnerable_version_ranges.sole)
      end

      test "it is disabled for a end of life ecosystem when the repository has a feature flag enabled", skip_enterprise: true do
        @repository.enable_feature("rust_beta")
        @vulnerability = create(:published_vulnerability, ecosystem: "go", with_ranges: 1)

        refute @provider.provides_data_for?(@repository, @vulnerability.vulnerable_version_ranges.sole)
      end

      test "the end of life list has higher precedent than the normal list", skip_enterprise: true do
        @repository.enable_feature("eol_composer")
        @vulnerability = create(:published_vulnerability, ecosystem: "composer", with_ranges: 1)

        refute @provider.provides_data_for?(@repository, @vulnerability.vulnerable_version_ranges.sole)
      end
    end

    context "#process_detections?" do
      test "it is always true" do
        assert @provider.process_detections?
      end
    end
  end

  context "DG-API", skip_enterprise: true do
    DependencyGraph::Ecosystems::SUPPORTED.each do |supported_ecosystem|
      test "it provides data for #{supported_ecosystem.name} by default" do
        @repository.disable_feature(DependencyGraph::VulnerableDependencyProvider::DGP_NPM_FEATURE_FLAG)
        @vulnerability = create(:published_vulnerability, ecosystem: supported_ecosystem.name, with_ranges: 1)

        assert DependencyGraph::VulnerableDependencyProvider::DG_API.provides_data_for?(
          @repository,
          @vulnerability.vulnerable_version_ranges.sole
        )
      end
    end

    test "it does not provide data for npm if the repository has the end of life feature flag" do
      @repository.enable_feature(DependencyGraph::VulnerableDependencyProvider::DGP_NPM_FEATURE_FLAG)
      @vulnerability = create(:published_vulnerability, ecosystem: "npm", with_ranges: 1)

      refute DependencyGraph::VulnerableDependencyProvider::DG_API.provides_data_for?(
        @repository,
        @vulnerability.vulnerable_version_ranges.sole
      )
    end

    test "advisory vulnerability detections are always processed" do
      assert DependencyGraph::VulnerableDependencyProvider::DG_API.process_detections?
    end
  end

  context "DGP", skip_enterprise: true do
    DependencyGraph::Ecosystems::SUPPORTED.each do |supported_ecosystem|
      test "it does not provide data for #{supported_ecosystem.name} by default" do
        @repository.disable_feature(DependencyGraph::VulnerableDependencyProvider::DGP_NPM_FEATURE_FLAG)
        @vulnerability = create(:published_vulnerability, ecosystem: supported_ecosystem.name, with_ranges: 1)

        refute DependencyGraph::VulnerableDependencyProvider::DGP.provides_data_for?(
          @repository,
          @vulnerability.vulnerable_version_ranges.sole
        )
      end
    end

    test "it provides data for npm if the repository has the  beta feature flag" do
      @repository.enable_feature(DependencyGraph::VulnerableDependencyProvider::DGP_NPM_FEATURE_FLAG)
      @vulnerability = create(:published_vulnerability, ecosystem: "npm", with_ranges: 1)

      assert DependencyGraph::VulnerableDependencyProvider::DGP.provides_data_for?(
        @repository,
        @vulnerability.vulnerable_version_ranges.sole
      )
    end

    context "::process_beta_provider_detections?" do
      test "it is enabled with the feature flag", feature_enabled: DependencyGraph::VulnerableDependencyProvider::DGP_BETA_DETECTIONS_FLAG do
        assert DependencyGraph::VulnerableDependencyProvider::DGP.process_detections?
      end

      test "it is disabled without the feature flag", feature_disabled: DependencyGraph::VulnerableDependencyProvider::DGP_BETA_DETECTIONS_FLAG do
        refute DependencyGraph::VulnerableDependencyProvider::DGP.process_detections?
      end
    end
  end

  context "GHES environments", enterprise_only: true do
    DependencyGraph::Ecosystems::SUPPORTED.each do |supported_ecosystem|
      test "DG API always provides #{supported_ecosystem}" do
        @repository.enable_feature(DependencyGraph::VulnerableDependencyProvider::DGP_NPM_FEATURE_FLAG)
        @vulnerability = create(:published_vulnerability, ecosystem: supported_ecosystem.name, with_ranges: 1)

        assert DependencyGraph::VulnerableDependencyProvider::DG_API.provides_data_for?(
          @repository,
          @vulnerability.vulnerable_version_ranges.sole
        )
      end

      test "DGP never provides #{supported_ecosystem}" do
        @repository.enable_feature(DependencyGraph::VulnerableDependencyProvider::DGP_NPM_FEATURE_FLAG)
        @vulnerability = create(:published_vulnerability, ecosystem: supported_ecosystem.name, with_ranges: 1)

        refute DependencyGraph::VulnerableDependencyProvider::DGP.provides_data_for?(
          @repository,
          @vulnerability.vulnerable_version_ranges.sole
        )
      end
    end
  end
end
