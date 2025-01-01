# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependency_review_test_helper"

class ReviewSummaryTest < GitHub::TestCase
  include DependencyReviewTestHelper

  setup do
    @review_summary = DependencyReview::ReviewSummary.from_twirp(stubbed_snapshot_diff_response)
  end

  test "it correctly counts the number of added dependencies" do
    assert_equal 1, @review_summary.added_dependencies.count
  end

  test "it correctly counts the number of updated dependencies" do
    assert_equal 1, @review_summary.updated_dependencies.count
  end

  test "it correctly counts the number of removed dependencies" do
    assert_equal 3, @review_summary.removed_dependencies.count
  end

  test "it correctly calculates has_changes?" do
    # fixture has some items already
    assert_equal true, @review_summary.has_changes?

    # try an empty one
    empty_review_summary = DependencyReview::ReviewSummary.new(manifests: [])
    assert_equal false, empty_review_summary.has_changes?
  end

  test "it loads vulnerabilities correctly" do
    mock_loader = Minitest::Mock.new
    expected_range_ids = [@review_summary.added_dependencies.map { |d| d.github_vulnerability_range_ids },
      @review_summary.updated_dependencies.map { |d| d.github_vulnerability_range_ids }].flatten

    vulns = {
      1 => create_vulnerability("critical", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
      2 => create_vulnerability("critical", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
      3 => create_vulnerability("critical", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
      4 => create_vulnerability("critical", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
      5 => create_vulnerability("critical", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
    }
    mock_loader.expect(:get_all_vulnerabilities_for_range_ids, vulns, [expected_range_ids])
    @review_summary.load_vulnerabilities(vulnerability_loader: mock_loader)
    mock_loader.verify

    daemons_dependency = @review_summary.updated_dependencies.find { |x| x.package_name == "daemons" }
    pandas_dependency = @review_summary.added_dependencies.find { |x| x.package_name == "pandas" }

    assert_equal true, daemons_dependency.vulnerabilities.include?(vulns[1])
    assert_equal true, daemons_dependency.vulnerabilities.include?(vulns[2])
    assert_equal true, daemons_dependency.vulnerabilities.include?(vulns[3])
    assert_equal 3, daemons_dependency.vulnerabilities.count

    assert_equal true, pandas_dependency.vulnerabilities.include?(vulns[4])
    assert_equal true, pandas_dependency.vulnerabilities.include?(vulns[5])
    assert_equal 2, pandas_dependency.vulnerabilities.count
  end

  test "it loads vulnerabilities on removals if decomposing updates" do
    twirp_response = build_get_snapshots_diff_response({
      repository_id: 1,
      base_sha: "378a18ae098da719db960260a5d942667ad22984",
      target_sha: "c18e6fa46ab9caef2710bdc2711157276c57b5f1",
      changed_manifests: [
        {
          type: 1,
          file_path: "Gemfile",
          dependencies: [
            {
              name: "vuln_package",
              target_version: "",
              change_type: 2,
              base_version: "1.0.1",
              github_vulnerability_range_ids: [1]
            },
          ]
        },
      ],
      base_sha_created_at: Time.now - 1.day,
      target_sha_created_at: Time.now
    })

    review_summary = DependencyReview::ReviewSummary.from_twirp(twirp_response)

    mock_loader = Minitest::Mock.new
    expected_range_ids = review_summary.removed_dependencies.map { |d| d.github_vulnerability_range_ids }.flatten.uniq

    vulns = {
      1 => create_vulnerability("moderate", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
    }

    mock_loader.expect(:get_all_vulnerabilities_for_range_ids, vulns, [expected_range_ids])
    review_summary.load_vulnerabilities(vulnerability_loader: mock_loader, decompose_updates: true)
    review_summary.sort_dependencies
    mock_loader.verify

    vuln_dependency = review_summary.removed_dependencies.find { |x| x.package_name == "vuln_package" }

    assert_equal true, vuln_dependency.vulnerabilities.include?(vulns[1])
  end

  test "it does not load vulnerabilities on removals if not decomposing updates" do
    twirp_response = build_get_snapshots_diff_response({
      repository_id: 1,
      base_sha: "378a18ae098da719db960260a5d942667ad22984",
      target_sha: "c18e6fa46ab9caef2710bdc2711157276c57b5f1",
      changed_manifests: [
        {
          type: 1,
          file_path: "Gemfile",
          dependencies: [
            {
              name: "vuln_package",
              target_version: "",
              change_type: 2,
              base_version: "1.0.1",
              github_vulnerability_range_ids: [1]
            },
          ]
        },
      ],
      base_sha_created_at: Time.now - 1.day,
      target_sha_created_at: Time.now
    })

    review_summary = DependencyReview::ReviewSummary.from_twirp(twirp_response)

    mock_loader = Minitest::Mock.new

    vulns = {
      1 => create_vulnerability("moderate", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
    }

    mock_loader.expect(:get_all_vulnerabilities_for_range_ids, vulns, [[]])
    review_summary.load_vulnerabilities(vulnerability_loader: mock_loader)
    review_summary.sort_dependencies
    mock_loader.verify

    vuln_dependency = review_summary.removed_dependencies.find { |x| x.package_name == "vuln_package" }

    assert_equal false, vuln_dependency.vulnerabilities.include?(vulns[1])
  end

  test "dependencies are sorted correctly" do
    twirp_response = build_get_snapshots_diff_response({
      repository_id: 1,
      base_sha: "378a18ae098da719db960260a5d942667ad22984",
      target_sha: "c18e6fa46ab9caef2710bdc2711157276c57b5f1",
      changed_manifests: [
        {
          type: 1,
          file_path: "Gemfile",
          dependencies: [
            {
              name: "added_B", #
              base_version: "1.0.0",
              change_type: 1
            },
            {
              name: "added_C_vuln",
              target_version: "1.0.3",
              change_type: 1,
              base_version: "1.0.1",
              github_vulnerability_range_ids: [2]
            },
            {
              name: "updated_C_vuln",
              target_version: "1.0.3",
              change_type: 3,
              base_version: "1.0.1",
              github_vulnerability_range_ids: [1, 3]
            },
            {
              name: "updated_A_vuln",
              target_version: "1.0.3",
              change_type: 3,
              base_version: "1.0.1",
              github_vulnerability_range_ids: [2, 4]
            },
            {
              name: "added_D_vuln",
              target_version: "1.0.3",
              change_type: 3,
              base_version: "1.0.1",
              github_vulnerability_range_ids: [2, 4]
            },
            {
              name: "added_A",
              base_version: "1.0.0",
              change_type: 1
            },
            {
              name: "removed_B",
              base_version: "1.3.0",
              change_type: 2
            },
            {
              name: "removed_A",
              base_version: "1.2.0",
              change_type: 2
            },
            {
              name: "updated_B",
              target_version: "1.0.3",
              change_type: 3,
              base_version: "1.0.1",
            },
            {
              name: "added_E_vuln",
              target_version: "1.0.3",
              change_type: 3,
              base_version: "1.0.1",
              github_vulnerability_range_ids: [2, 4]
            },
          ]
        },
      ],
      base_sha_created_at: Time.now - 1.day,
      target_sha_created_at: Time.now
    })

    review_summary = DependencyReview::ReviewSummary.from_twirp(twirp_response)

    mock_loader = Minitest::Mock.new
    expected_range_ids = [review_summary.added_dependencies.map { |d| d.github_vulnerability_range_ids },
      review_summary.updated_dependencies.map { |d| d.github_vulnerability_range_ids }].flatten.uniq

    vulns = {
      1 => create_vulnerability("moderate", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
      2 => create_vulnerability("low", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
      3 => create_vulnerability("critical", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
      4 => create_vulnerability("high", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
    }
    mock_loader.expect(:get_all_vulnerabilities_for_range_ids, vulns, [expected_range_ids])
    review_summary.load_vulnerabilities(vulnerability_loader: mock_loader)
    review_summary.sort_dependencies
    mock_loader.verify

    manifest = review_summary.manifests.first

    #sort priority is vulnerable first, then additions, updates, then removals, and then alphabetical
    #sort output should be updated_C_vuln, added_D_vuln, added_E_vuln, updated_A_vuln, added_C_vuln, added_A, added_B, updated_B, removed_A, removed_B

    # updated_C_vuln is first because it has the highest severity

    # added_D_vuln, added_E_vuln, and updated_A_vuln all have the same max severity
    # added_D_vuln & added_E_vuln are before updated_A_vuln because change type (additions before updates)
    # added_D_vuln & added_E_vuln are alphabetical

    # added_C_vuln has the lowest max severity

    # all remaining dependencies are simply sorted by change type and alphabetical order


    sort_order = %w[updated_C_vuln added_D_vuln added_E_vuln updated_A_vuln added_C_vuln added_A added_B updated_B removed_A removed_B]

    assert_equal sort_order, manifest.dependencies.map { |dep| dep.package_name }
  end

  test "advisories inside vuln deps are sorted correctly" do
    twirp_response = build_get_snapshots_diff_response({
      repository_id: 1,
      base_sha: "378a18ae098da719db960260a5d942667ad22984",
      target_sha: "c18e6fa46ab9caef2710bdc2711157276c57b5f1",
      changed_manifests: [
        {
          type: 1,
          file_path: "Gemfile",
          dependencies: [
            {
              name: "vuln_package",
              target_version: "1.0.3",
              change_type: 3,
              base_version: "1.0.1",
              github_vulnerability_range_ids: [1, 2, 3, 4, 5, 6]
            },
          ]
        },
      ],
      base_sha_created_at: Time.now - 1.day,
      target_sha_created_at: Time.now
    })

    review_summary = DependencyReview::ReviewSummary.from_twirp(twirp_response)

    mock_loader = Minitest::Mock.new
    expected_range_ids = [review_summary.added_dependencies.map { |d| d.github_vulnerability_range_ids },
      review_summary.updated_dependencies.map { |d| d.github_vulnerability_range_ids }].flatten.uniq

    vulns = {
      1 => create_vulnerability("moderate", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
      2 => create_vulnerability("low", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
      3 => create_vulnerability("high", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
      4 => create_vulnerability("critical", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
      5 => create_vulnerability("high", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
      6 => create_vulnerability("moderate", "> 1.0.0, < 2.0.0", "2.0.0", "GHSA-rando-id", "Some vulnerability", "Ipso facto description texto"),
    }
    mock_loader.expect(:get_all_vulnerabilities_for_range_ids, vulns, [expected_range_ids])
    review_summary.load_vulnerabilities(vulnerability_loader: mock_loader)
    review_summary.sort_dependencies
    mock_loader.verify

    vulns_severity_order = review_summary.manifests.first.dependencies.first.vulnerabilities.map { |vuln| vuln.severity }.uniq

    sort_order = %w[critical high moderate low]

    assert_equal sort_order, vulns_severity_order
  end

  def create_vulnerability(severity, version_range, first_patched, ghsa_id, summary, description)
    DependencyReview::Vulnerability.new(
      severity: severity,
      vulnerable_version_range: version_range,
      first_patched_version: first_patched,
      advisory_ghsa_id: ghsa_id,
      advisory_summary: summary,
      advisory_description: description)
  end
end
