# typed: true
# frozen_string_literal: true

require "test_helper"
require "hydro/schemas/advisory_db/v0/entities/vulnerability_pb"

class AdvisoryDbEcosystemsV2Test < GitHub::TestCase
  setup do
    @test_preview_eco = T.must(AdvisoryDB::EcosystemsV2.get(:TEST_PREVIEW_ECO))
    @test_preview_eco_slug = :TEST_PREVIEW_ECO
  end

  test "PUBLIC is subset of SUPPORTED" do
    assert_subset AdvisoryDB::EcosystemsV2.supported,
                  AdvisoryDB::EcosystemsV2.public
  end

  test "DEPENDENCY_GRAPH_SUPPORTED is subset of SUPPORTED" do
    assert_subset AdvisoryDB::EcosystemsV2.supported,
                  AdvisoryDB::EcosystemsV2.dependency_graph_supported
  end

  test ".get fetches an ecosystem by its registration slug" do
    test_preview_eco = T.must(AdvisoryDB::EcosystemsV2.get(@test_preview_eco_slug))
    assert_equal test_preview_eco, @test_preview_eco
  end

  test ".by_name fetches an ecosystem by its name" do
    AdvisoryDB::EcosystemsV2.supported(include_purl_ecosystems: true).each do |ecosystem|
      ecosystem_name = ecosystem.name
      assert_equal ecosystem,
        AdvisoryDB::EcosystemsV2.by_name(ecosystem_name),
        "Expected to find an ecosystem with name #{ecosystem_name}"
    end
  end

  test ".by_label fetches an ecosystem by its label" do
    AdvisoryDB::EcosystemsV2.supported(include_purl_ecosystems: true).each do |ecosystem|
      ecosystem_label = ecosystem.label
      assert_equal ecosystem,
        AdvisoryDB::EcosystemsV2.by_label(ecosystem_label),
        "Expected to find an ecosystem with label #{ecosystem_label}"
    end
  end

  test "finds ecosystems matching known Hydro vulnerability ecosystem enum values" do
    AdvisoryDB::EcosystemsV2.supported(include_purl_ecosystems: true).each do |ecosystem|
      next if ecosystem == @test_preview_eco

      enum_value = ecosystem.hydro_enum_value
      vulnerability_payload = { package_ecosystem: enum_value }
      ecosystem = AdvisoryDB::EcosystemsV2.from_advisory_vulnerability(vulnerability_payload)
      refute_nil ecosystem, "Expected to find an ecosystem with enum value #{enum_value}"
    end
  end

  test ".label fetches an ecosystem label by its name" do
    AdvisoryDB::EcosystemsV2.supported(include_purl_ecosystems: true).each do |ecosystem|
      ecosystem_name = ecosystem.name
      ecosystem_label = ecosystem.label
      assert_equal ecosystem_label,
        AdvisoryDB::EcosystemsV2.label(ecosystem_name),
        "Expected ecosystem with name #{ecosystem_name} to have the label #{ecosystem_label}"
    end
  end

  test ".name fetches an ecosystem label by its label" do
    AdvisoryDB::EcosystemsV2.supported(include_purl_ecosystems: true).each do |ecosystem|
      ecosystem_name = ecosystem.name
      ecosystem_label = ecosystem.label
      assert_equal ecosystem_name,
        AdvisoryDB::EcosystemsV2.name(ecosystem_label),
        "Expected ecosystem with name #{ecosystem_name} to have the label #{ecosystem_label}"
    end
  end

  test ".purl_type fetches an ecosystem purl type by its name" do
    AdvisoryDB::EcosystemsV2.supported(include_purl_ecosystems: true).each do |ecosystem|
      ecosystem_name = ecosystem.name
      ecosystem_purl_type = ecosystem.purl_type
      assert_equal ecosystem_purl_type,
        AdvisoryDB::EcosystemsV2.purl_type(ecosystem_name),
        "Expected ecosystem with name #{ecosystem_name} to have the purl_type #{ecosystem_purl_type}"
    end
  end

  test "all registered hydro enum values are a subset of hydro vulnerability ecosystem enum" do
    hydro_enums = Hydro::Schemas::AdvisoryDb::V0::Entities::Vulnerability::Ecosystem.constants
    schema_ecosystems = AdvisoryDB::EcosystemsV2.
      supported(include_purl_ecosystems: true).
      reject { |ecosystem| ecosystem == @test_preview_eco }.
      map(&:hydro_enum_value).
      compact
    assert_subset hydro_enums, schema_ecosystems
  end

  # TEMPORARY
  test "SUPPORTED_PURL_TYPES has no overlap with SUPPORTED by default" do
    refute_overlap AdvisoryDB::EcosystemsV2.supported,
                   AdvisoryDB::EcosystemsV2::SUPPORTED_PURL_TYPES
  end

  # TEMPORARY
  test "SUPPORTED can optionally include SUPPORTED_PURL_TYPES" do
    assert_subset AdvisoryDB::EcosystemsV2.supported(include_purl_ecosystems: true),
                  AdvisoryDB::EcosystemsV2::SUPPORTED_PURL_TYPES
  end

  # TEMPORARY
  test "PUBLIC_PURL_TYPES is subset of SUPPORTED_PURL_TYPES" do
    assert_subset AdvisoryDB::EcosystemsV2::SUPPORTED_PURL_TYPES,
                  AdvisoryDB::EcosystemsV2::PUBLIC_PURL_TYPES
  end

  # TEMPORARY
  test "PUBLIC_PURL_TYPES has no overlap with PUBLIC by default" do
    refute_overlap AdvisoryDB::EcosystemsV2.public,
                   AdvisoryDB::EcosystemsV2::PUBLIC_PURL_TYPES
  end

  # TEMPORARY
  test "PUBLIC can optionally include PUBLIC_PURL_TYPES" do
    assert_subset AdvisoryDB::EcosystemsV2.public(include_purl_ecosystems: true),
                  AdvisoryDB::EcosystemsV2::PUBLIC_PURL_TYPES
  end

  # TEMPORARY
  test "SUPPORTED_NAMES can optionally include SUPPORTED_PURL_TYPES_NAMES" do
    assert_subset AdvisoryDB::EcosystemsV2.supported_names(include_purl_ecosystems: true),
                  AdvisoryDB::EcosystemsV2::SUPPORTED_PURL_TYPES_NAMES
  end

  # TEMPORARY
  test "PUBLIC_NAMES can optionally include PUBLIC_PURL_TYPES_NAMES" do
    assert_subset AdvisoryDB::EcosystemsV2.public_names(include_purl_ecosystems: true),
                  AdvisoryDB::EcosystemsV2::PUBLIC_PURL_TYPES_NAMES
  end

  # TEMPORARY
  test "PUBLIC_LABELS can optionally include PUBLIC_PURL_TYPES_LABELS" do
    assert_subset AdvisoryDB::EcosystemsV2.public_labels(include_purl_ecosystems: true),
                  AdvisoryDB::EcosystemsV2::PUBLIC_PURL_TYPES_LABELS
  end

  # TEMPORARY
  test ".get can fetch purl type ecosystems by their registration slug" do
    apk = T.must(AdvisoryDB::Ecosystems::PurlTypeRegister.get(:APK))
    assert_equal apk, AdvisoryDB::EcosystemsV2.get(:APK)
  end

  def assert_subset(superset, subset)
    intersection = superset & subset
    assert_same_elements subset, intersection, "Expected #{subset} to be a subset of #{superset}"
  end

  def refute_overlap(set1, set2)
    intersection = set1 & set2
    assert_empty intersection, "Expected #{set1} not to have any overlap with #{set2}"
  end
end
