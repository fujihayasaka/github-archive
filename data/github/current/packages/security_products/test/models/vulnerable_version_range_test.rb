# typed: true
# frozen_string_literal: true

require "test_helper"

class VulnerableVersionRangeTest < GitHub::TestCase
  test "is not valid without a vulnerability" do
    vvr = build :vulnerable_version_range, vulnerability: nil
    refute vvr.valid?
    assert_includes vvr.errors.messages[:vulnerability], "can't be blank"
  end

  test "it does not allow spaces in 'affects' field" do
    vvr = build :vulnerable_version_range, affects: "name with space"
    refute vvr.valid?
    assert_equal({ affects: ["can not contain whitespace"] }, vvr.errors.messages)
  end

  test "does not allow an ecosystem that is not in the list we support" do
    vvr = build :vulnerable_version_range, ecosystem: "VisualBasic"
    refute vvr.valid?
    assert_equal vvr.errors.messages, { ecosystem: ["is not included in the list"] }
    # also does not allow nil ecosystem
    vvr = build :vulnerable_version_range, ecosystem: nil
    refute vvr.valid?
    assert_equal vvr.errors.messages, { ecosystem: ["is not included in the list", "can't be blank"] }
  end

  # Valid ecosystems
  %w[
    composer
    maven
    npm
    nuget
    go
    other
    pip
    RubyGems
  ].each do |ecosystem|
    test "should allow ecosystem: #{ecosystem}" do
      vvr = build :vulnerable_version_range, ecosystem: ecosystem
      assert vvr.valid?
    end
  end

  # Valid requirements
  [
    "= 1",
    "> 0",
    ">= 1.2",
    "< 2",
    "<= 2.0",
    ">= 2.0, < 2.5",
    ">= 5.0.0, <= 5.2.0",
  ].each do |requirement_string|
    test "should allow requirement: #{requirement_string}" do
      vvr = build :vulnerable_version_range, requirements: requirement_string
      assert vvr.valid?, "this requirement string should be valid: '#{requirement_string}'"
    end
  end

  # Invalid requirements
  [
    "?invalid?",
    "2",
    "a1b",
    "=< 3",
    "=< 4",
    " < 1.0",
    "> 1.0, > 2",
    ">= 1.0 , < 2",
    "< 1.2.3,",
    "> 1, > 2", # can't re-use >
    "> 1.1, >= 2.2", # can't re-use >
    "< 1.1.0, > 2.2.1", # can't start with < if two-part
    "< 1.1, < 123.0", # can't re-use <
  ].each do |requirement_string|
    test "should not allow requirement: #{requirement_string}" do
      vvr = build :vulnerable_version_range, requirements: requirement_string
      refute vvr.valid?, "this requirement string should be invalid: '#{requirement_string}'"
      assert_equal({ requirements: ["not a valid requirements string"] }, vvr.errors.messages)
    end
  end

  test "does not allow blank requirements" do
    requirement_string = ""
    vvr = build :vulnerable_version_range, requirements: requirement_string
    refute vvr.valid?, "this requirement string should be invalid: '#{requirement_string}'"
    assert_predicate vvr.errors[:requirements], :any?, "can't be blank"
    # assert_equal({ :requirements => ["not a valid requirements string."] }, vvr.errors.messages)
  end

  test "updates updated_at of parent vulnerability when updated" do
    vulnerability = Timecop.freeze("2019-10-01") { create :published_vulnerability }
    range = vulnerability.vulnerable_version_ranges.first
    orig_update_time = vulnerability.updated_at

    Timecop.freeze("2019-10-02") { range.touch }

    assert_operator vulnerability.reload.updated_at, :>, orig_update_time
  end

  # .disclosed
  test "only ranges with a public ecosystem are disclosed" do
    range_a = create(:vulnerable_version_range, :published, ecosystem: "maven")
    range_b = create(:vulnerable_version_range, :published, ecosystem: "pip")
    range_c = create(:vulnerable_version_range, :published, ecosystem: "test_preview_eco")

    disclosed_ranges = VulnerableVersionRange.disclosed
    assert_includes disclosed_ranges, range_a
    assert_includes disclosed_ranges, range_b
    refute_includes disclosed_ranges, range_c
  end

  test "ranges are disclosed even when the associated vulnerability has other ranges that are not disclosed" do
    range_a = create(:vulnerable_version_range, :published, ecosystem: "maven")
    vulnerability = range_a.vulnerability
    range_b = create(:vulnerable_version_range, :published, ecosystem: "test_preview_eco", vulnerability: vulnerability)

    disclosed_ranges = VulnerableVersionRange.disclosed
    assert_includes disclosed_ranges, range_a
    refute_includes disclosed_ranges, range_b
  end

  test "only ranges which do not belong to simulation vulnerabilities are disclosed" do
    vuln_a = create(:published_vulnerability, simulation: true)
    range_a = vuln_a.vulnerable_version_ranges.first
    vuln_b = create(:published_vulnerability, simulation: false)
    range_b = vuln_b.vulnerable_version_ranges.first

    disclosed_ranges = VulnerableVersionRange.disclosed
    refute_includes disclosed_ranges, range_a
    assert_includes disclosed_ranges, range_b
  end

  test "withdraws associated repository vulnerability alerts when destroyed" do
    range = create(:vulnerable_version_range, :published)
    create(:repository_vulnerability_alert, :open, vulnerable_version_range: range)
    create(:repository_vulnerability_alert, :closed, vulnerable_version_range: range)
    alerts = RepositoryVulnerabilityAlert.without_default_scope.where(vulnerable_version_range_id: range.id)

    assert_enqueued_jobs(1, only: WithdrawRepositoryVulnerabilityAlertsJob) do
      range.destroy
    end

    assert_equal 0, alerts.withdrawn.count

    assert_changes -> { alerts.not_withdrawn.count }, from: 2, to: 0 do
      perform_enqueued_jobs(only: WithdrawRepositoryVulnerabilityAlertsJob)
    end

    assert_equal 2, alerts.withdrawn.count
  end

  context "#affects_versions?" do
    test "with and operator" do
      range = create(:vulnerable_version_range, :published, ecosystem: "RubyGems", requirements: "<= 1.5.2")

      assert range.affects_versions?(["1.0.0", "1.3.0", "1.5.2"], operator: :and)
      assert range.affects_versions?(["1.0.0", "1.3.0", "1.5.2"]) # should be :and by default
      refute range.affects_versions?(["5.0.0", "1.3.0", "1.5.2"], operator: :and)
      refute range.affects_versions?(["5.0.0", "1.3.0", "1.5.2"])
    end

    test "with or operator" do
      range = create(:vulnerable_version_range, :published, ecosystem: "RubyGems", requirements: "<= 1.5.2")

      assert range.affects_versions?(["5.0.0", "2.3.0", "1.5.1"], operator: :or)
      refute range.affects_versions?(["5.0.0", "5.3.0", "5.5.2"], operator: :or)
    end

    test "python versions" do
      range = create(:vulnerable_version_range, :published, ecosystem: "pip", requirements: ">= 1.0, < 1.5.beta")

      assert_equal Dependabot::Versioning::Python::Version, range.dependabot_version_class
      assert range.affects_versions?(["1.0.0"])
      assert range.affects_versions?(["1.0.1"])
      refute range.affects_versions?(["1.5.0"])
      refute range.affects_versions?(["1.5.1"])

      # testing edge case involving issues with lower bound prerelease
      range2 = create(:vulnerable_version_range, :published, ecosystem: "pip", requirements: ">= 2.5.0-pre")

      assert range2.affects_versions?(["2.5.0+gc.1"])
      assert range2.affects_versions?(["2.5.0-pre"])
    end

    test "composer versions" do
      range = create(:vulnerable_version_range, :published, ecosystem: "composer", requirements: "> 1.0.1-rc2")

      assert_equal Dependabot::Versioning::Composer::Version, range.dependabot_version_class
      refute range.affects_versions?(["1.0.0"])
      refute range.affects_versions?(["1.0.1-rc1"])
      assert range.affects_versions?(["1.0.2-rc1"])
      assert range.affects_versions?(["1.5.0"])
    end

    test "erlang versions" do
      range = create(:vulnerable_version_range, :published, ecosystem: "erlang", requirements: "<= 5.0.0")

      assert_equal Dependabot::Versioning::Hex::Version, range.dependabot_version_class
      assert range.affects_versions?(["1.0.0"])
      refute range.affects_versions?(["5.0.0+gc.1"])
      refute range.affects_versions?(["5.0.1"])
    end

    test "actions versions" do
      range = create(:vulnerable_version_range, :published, ecosystem: "actions", requirements: "> 6.4.3")

      assert_equal Dependabot::Versioning::GithubActions::Version, range.dependabot_version_class
      assert range.affects_versions?(["7.0.0"])
      assert range.affects_versions?(["v6.4.4"])
      refute range.affects_versions?(["6.4.3"])
    end

    test "go versions" do
      range = create(:vulnerable_version_range, :published, ecosystem: "go", requirements: "> 2.5.0, <= 3.0.0")

      assert_equal Dependabot::Versioning::GoModules::Version, range.dependabot_version_class
      assert range.affects_versions?(["v2.6.4"])
      refute range.affects_versions?(["v2.4.3"])
    end

    test "maven versions" do
      range = create(:vulnerable_version_range, :published, ecosystem: "maven", requirements: ">= 2.5.0-beta")

      assert_equal Dependabot::Versioning::Maven::Version, range.dependabot_version_class
      assert range.affects_versions?(["2.5.0"])
      refute range.affects_versions?(["2.5.0ab"])
      refute range.affects_versions?(["2.5.0-alpha"])
    end

    test "npm versions" do
      range = create(:vulnerable_version_range, :published, ecosystem: "npm", requirements: ">= 2.5.0.pre1")

      assert_equal Dependabot::Versioning::NpmAndYarn::Version, range.dependabot_version_class
      assert range.affects_versions?(["v2.5.0"])
      assert range.affects_versions?(["2.5.0.pre2"])
      refute range.affects_versions?(["2.4.9"])
    end

    test "nuget versions" do
      range = create(:vulnerable_version_range, :published, ecosystem: "nuget", requirements: ">= 2.5.0")

      assert_equal Dependabot::Versioning::Nuget::Version, range.dependabot_version_class
      assert range.affects_versions?(["2.5.0+build"])
      refute range.affects_versions?(["2.5.0.pre"])
    end

    test "pub versions" do
      range = create(:vulnerable_version_range, :published, ecosystem: "pub", requirements: ">= 2.5.0-beta2")

      assert_equal Dependabot::Versioning::Pub::Version, range.dependabot_version_class
      assert range.affects_versions?(["2.5.0+build"])
      refute range.affects_versions?(["2.5.0-beta1"])
    end

    test "rust versions" do
      range = create(:vulnerable_version_range, :published, ecosystem: "rust", requirements: ">= 2.5.0-pre2")

      assert_equal Dependabot::Versioning::Cargo::Version, range.dependabot_version_class
      assert range.affects_versions?(["2.5.0+build"])
      refute range.affects_versions?(["2.5.0-pre1"])
    end

    test "rubygems versions" do
      range = create(:vulnerable_version_range, :published, ecosystem: "RubyGems", requirements: ">= 1.0.0, <= 1.8.5.b")

      assert_equal Dependabot::Versioning::Bundler::Version, range.dependabot_version_class
      assert range.affects_versions?(["1.8.4"])
      assert range.affects_versions?(["1.8.5.b"])
      refute range.affects_versions?(["1.8.5"])
      refute range.affects_versions?(["0.8.5"])
    end

    test "other ecosystem range" do
      range = create(:vulnerable_version_range, :published, ecosystem: "other", requirements: "<= 3.5.4")

      assert_equal Dependabot::Versioning::Version, range.dependabot_version_class
      assert range.affects_versions?(["3.5.2"])
      refute range.affects_versions?(["3.6"])
    end

    test "gracefully rejects invalid version strings" do
      range = create(:vulnerable_version_range, :published, ecosystem: "pip", requirements: ">= 1.0, < 1.5.beta")

      refute range.affects_versions?(%w[boop beep boop])
      assert range.affects_versions?(["boop", "beep", "1.1.0"], operator: :or)
    end
  end

  context "scoped vulnerabilities" do
    test "can belong to both scoped and unscoped vulnerabilities" do
      vuln = create(:vulnerability)
      vvr = create(:vulnerable_version_range, vulnerability: vuln)
      open_source_vuln = create(:open_source_vulnerability, id: vuln.id, ghsa_id: vuln.ghsa_id)
      vuln.reload

      assert_same_elements vuln.vulnerable_version_ranges, open_source_vuln.vulnerable_version_ranges
      assert_nil vvr.scoped_vulnerability
      vvr.reload
      assert_equal vvr.with_scope(:open_source).scoped_vulnerability, open_source_vuln
    end

    test "can belong to an innersource vulnerability" do
      vuln = create(:vulnerability)
      vvr = create(:vulnerable_version_range, vulnerability: vuln)
      innersource_vuln = create(:innersource_vulnerability, id: vuln.id, ghsa_id: vuln.ghsa_id)
      vuln.reload

      assert_same_elements vuln.vulnerable_version_ranges, innersource_vuln.vulnerable_version_ranges
      assert_nil vvr.scoped_vulnerability
      vvr.reload
      assert_equal vvr.with_scope(:innersource).scoped_vulnerability, innersource_vuln
    end

    test "vulnerability can be optional and scoped vulnerability required" do
      disable_feature_flag(:innersource_sync)
      disable_feature_flag(:innersource_sync_direction_reverse)

      scoped_vuln = create(:scoped_vulnerability)
      assert_raises ActiveRecord::RecordInvalid do
        create(:vulnerable_version_range, vulnerability_id: scoped_vuln.id)
      end

      enable_feature_flag(:innersource_sync)
      enable_feature_flag(:innersource_sync_direction_reverse)

      vvr = create(:vulnerable_version_range, vulnerability_id: scoped_vuln.id)
      vvr.reload

      assert_predicate vvr, :valid?
      assert_nil vvr.vulnerability
      refute_nil vvr.with_scope(:open_source).scoped_vulnerability
    end
  end
end
