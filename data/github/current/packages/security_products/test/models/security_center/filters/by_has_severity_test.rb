# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Filters
    class ByHasSeverityTest < GitHub::TestCase
      fixtures do
        @org = create(:organization)

        @all_repos = [
          @all_sev = create_repo("all-severities", owner: @org,
            dependabot_severities: { critical: 1, high: 2, moderate: 3, low: 4 },
            code_scanning_severities: { critical: 1, high: 2, medium: 3, low: 4, error: 5, warning: 6, note: 7 }),
          @dbot_sev = create_repo("dbot-severities", owner: @org,
            dependabot_severities: { critical: 1, high: 2, moderate: 3, low: 4 }),
          @cs_sev = create_repo("cs-severities", owner: @org,
            code_scanning_severities: { critical: 1, high: 2, medium: 3, low: 4, error: 5, warning: 6, note: 7 }),
          @cs_err = create_repo("cs-error", owner: @org,
            code_scanning_severities: { error: 5 }),
          @cs_warn = create_repo("cs-warning", owner: @org,
            code_scanning_severities: { warning: 6 }),
          @cs_note = create_repo("cs-note", owner: @org,
            code_scanning_severities: { note: 7 }),
          @only_crit = create_repo("only-critical", owner: @org,
            dependabot_severities: { critical: 1 },
            code_scanning_severities: { critical: 1 }),
          @zero_crit = create_repo("zero-critical", owner: @org,
            dependabot_severities: { critical: 0 },
            code_scanning_severities: { critical: 0 }),
          @no_sev = create_repo("no-severities", owner: @org),
        ]
      end

      setup do
        @base_rel = RepositorySecurityCenterConfig.all
      end

      context "#apply" do
        test "filters by severity with inclusive filters" do
          assert_query_count(1) do
            ByHasSeverity.new(["critical"], []).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@all_sev, @dbot_sev, @cs_sev, @only_crit]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByHasSeverity.new(%w[medium low], []).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@all_sev, @dbot_sev, @cs_sev]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByHasSeverity.new(["informational"], []).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@all_sev, @cs_sev, @cs_err, @cs_warn, @cs_note]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "filters by severity with exclusive filters" do
          assert_query_count(1) do
            ByHasSeverity.new([], ["critical"]).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@cs_err, @cs_warn, @cs_note, @zero_crit, @no_sev]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByHasSeverity.new([], %w[medium low]).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@cs_err, @cs_warn, @cs_note, @only_crit, @zero_crit, @no_sev]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByHasSeverity.new([], ["informational"]).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@dbot_sev, @only_crit, @zero_crit, @no_sev]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "filters by severity with both inclusive and exclusive filters" do
          assert_query_count(1) do
            ByHasSeverity.new(["critical"], ["medium"]).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@dbot_sev, @only_crit]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "doesn't filter if no filters are provided" do
          assert_query_count(1) do
            ByHasSeverity.new(nil, nil).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @all_repos
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(0) do
            ByHasSeverity.new([], []).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @all_repos
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "returns proper result for is_empty?" do
          assert ByHasSeverity.new(nil, nil).is_empty?
          assert ByHasSeverity.new([], []).is_empty?
          refute ByHasSeverity.new(["critical"], []).is_empty?
          refute ByHasSeverity.new([], ["critical"]).is_empty?
        end

        test "filters by unrecognized filter values" do
          filter_value = "unrecognized"

          assert_query_count(0) do
            ByHasSeverity.new([filter_value], nil).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = []
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByHasSeverity.new([], [filter_value]).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @all_repos
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end
      end

      def create_repo(name, owner:, dependabot_severities: {}, code_scanning_severities: {}, secret_scanning_severities: {})
        create(:private_repository, name: name, owner: owner).tap do |r|
          create(
            :repository_security_center_config,
            repository: r,
            ghas_enabled: true,
          )

          dependabot_severities.each do |severity, count|
            create(:security_center_alert_severity, repository: r, feature_type: :dependabot_alerts, severity: severity, alert_count: count)
          end
          code_scanning_severities.each do |severity, count|
            create(:security_center_alert_severity, repository: r, feature_type: :code_scanning, severity: severity, alert_count: count)
          end
          secret_scanning_severities.each do |severity, count|
            create(:security_center_alert_severity, repository: r, feature_type: :secret_scanning, severity: severity, alert_count: count)
          end
        end
      end
    end
  end
end
