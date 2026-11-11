# frozen_string_literal: true

require "test_helper"

class EcosystemsTest < ActiveSupport::TestCase
  setup do
    @all_ecosystems = Set.new(AdvisoryDB.ecosystems)
    @curated_ecosystems = Set.new(AdvisoryDB.curated_ecosystems)
    @curator_publishable_ecosystems = Set.new(AdvisoryDB.curator_publishable_ecosystems)

    # Allow other feature flag checks beyond the expected calls below
    AdvisoryDB::Features.stubs(:enabled?).returns(false)
  end

  test "curated is subset of all ecosystems, and curator publishable is subset of that" do
    assert_subset @all_ecosystems, @curated_ecosystems
    assert_subset @curated_ecosystems, @curator_publishable_ecosystems
  end

  test "all curated ecosystems have entries in hash maps" do
    assert_equal @curated_ecosystems, Set.new(AdvisoryDB::Config::Ecosystems::ECOSYSTEM_LABELS.keys)
    assert_equal @curated_ecosystems, Set.new(AdvisoryDB::Config::Ecosystems::ECOSYSTEM_COLORS.keys)
    assert_equal @curated_ecosystems, Set.new(AdvisoryDB::Config::Ecosystems::ECOSYSTEM_DEPENDENCY_GRAPH_MAP.keys)
  end

  test "there is no overlap between curator publishable and auto-publishable ecosystems" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_purl_ecosystems_inbox").at_least_once.returns(true)

    refute_subset @curator_publishable_ecosystems, Set.new(AdvisoryDB.auto_publishable_ecosystems)
  end

  test "AdvisoryDB.ecosystems includes purl types when feature flagged" do
    purl_type_ecosystems = Set.new(AdvisoryDB::Config::Ecosystems::PURL_TYPE_ECOSYSTEMS)

    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_purl_ecosystems_inbox").at_least_once.returns(false)
    refute_subset Set.new(AdvisoryDB.ecosystems), purl_type_ecosystems

    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_purl_ecosystems_inbox").at_least_once.returns(true)
    assert_subset Set.new(AdvisoryDB.ecosystems), purl_type_ecosystems
  end

  test "AdvisoryDB.ecosystems includes purl types when dotcom feature flagged" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_purl_ecosystems_inbox").at_least_once.returns(false)
    purl_type_ecosystems = Set.new(AdvisoryDB::Config::Ecosystems::PURL_TYPE_ECOSYSTEMS)

    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_purl_ecosystems").at_least_once.returns(false)
    refute_subset Set.new(AdvisoryDB.ecosystems), purl_type_ecosystems

    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_purl_ecosystems").at_least_once.returns(true)
    assert_subset Set.new(AdvisoryDB.ecosystems), purl_type_ecosystems
  end

  test "AdvisoryDBToolkit's ecosystem hash matches advisory db's publishable ecosystems" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_purl_ecosystems_inbox").at_least_once.returns(true)

    publishable_ecosystems = Set.new(AdvisoryDB.publishable_ecosystems)
    assert_equal publishable_ecosystems, Set.new(AdvisoryDBToolkit::Ecosystems::ECOSYSTEM_OSV_MAP.keys)
  end

  def assert_subset(superset, subset)
    assert_empty (subset - superset), "Expected #{subset} to be a subset of #{superset}"
  end

  def refute_subset(superset, subset)
    refute_empty (subset - superset), "Expected #{subset} not to be a subset of #{superset}"
  end
end
