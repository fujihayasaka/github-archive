# typed: true
# frozen_string_literal: true

require "test_helper"
require "hydro/schemas/advisory_db/v0/entities/vulnerability_pb"

class AdvisoryDbEcosystemsTest < GitHub::TestCase
  test "DEPENDENCY_GRAPH_SUPPORTED is subset of SUPPORTED" do
    assert_subset AdvisoryDB::Ecosystems.supported(include_purl_ecosystems: true),
                  AdvisoryDB::Ecosystems.dependency_graph_supported
  end

  test "INTERNAL_ADVISORY_DB_SCHEMA_ECOSYSTEM_TYPES is a subset of hydro vulnerability ecosystem enum" do
    hydro_enums = Hydro::Schemas::AdvisoryDb::V0::Entities::Vulnerability::Ecosystem.constants
    schema_ecosystems = AdvisoryDB::Ecosystems.internal_ecosystem_types(include_purl_ecosystems: true)
    assert_subset hydro_enums, schema_ecosystems
  end

  test "INTERNAL_ADVISORY_DB_SCHEMA_ECOSYSTEM_TYPES maps to ecosystem constants" do
    AdvisoryDB::Ecosystems.internal_ecosystem_types(include_purl_ecosystems: true).each do |ecosystem_type|
      AdvisoryDB::Ecosystems.const_get(ecosystem_type)
    end
  end

  test "INTERNAL_ADVISORY_DB_SCHEMA_ECOSYSTEM_TYPES is subset of SUPPORTED" do
    schema_ecosystems = AdvisoryDB::Ecosystems.internal_ecosystem_types(include_purl_ecosystems: true).map do |ecosystem|
      AdvisoryDB::Ecosystems.const_get(ecosystem)
    end
    assert_subset AdvisoryDB::Ecosystems.supported(include_purl_ecosystems: true),
                  schema_ecosystems
  end

  # TEMPORARY
  test "v1 ecosystems match v2 ecosystems" do
    v1_ecosystems = AdvisoryDB::Ecosystems.supported(include_purl_ecosystems: true)
    assert_equal v1_ecosystems.size, AdvisoryDB::EcosystemsV2.supported(include_purl_ecosystems: true).size

    v1_ecosystems.each do |v1_ecosystem|
      v2_ecosystem = T.must(AdvisoryDB::EcosystemsV2.by_name(v1_ecosystem.name))
      assert_equal v1_ecosystem.name, v2_ecosystem.name
      assert_equal v1_ecosystem.label, v2_ecosystem.label
      assert_equal v1_ecosystem.description, v2_ecosystem.description
      assert_equal v1_ecosystem.purl_type, v2_ecosystem.purl_type
      assert_equal v1_ecosystem.public?, v2_ecosystem.public?
    end
  end

  def assert_subset(superset, subset)
    assert_empty (subset - superset), "Expected #{subset} to be a subset of #{superset}"
  end
end
