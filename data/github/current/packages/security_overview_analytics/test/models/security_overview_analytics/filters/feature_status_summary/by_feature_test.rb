# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    module FeatureStatusSummary
      class ByFeatureTest < GitHub::TestCase
        fixtures do
          @biz = create(:business)
          @org = create(:organization, business: @biz)

          @all_repos = [
            (@repo_cs_enabled = create_repo("#{@org}-cs-enabled-repo", owner: @org,
              features: {
                code_scanning: { status: :enrolled, count: 1 },
                code_scanning_auto_codeql: { status: :enrolled, count: 0 },
              }
            )),
            (@repo_ss_enabled = create_repo("#{@org}-ss-enabled-repo", owner: @org,
              features: {
                secret_scanning: { status: :enrolled, count: 2 },
              }
            )),
            (@repo_cs_ss_enabled = create_repo("#{@org}-cs-ss-enabled-repo", owner: @org,
              features: {
                code_scanning: { status: :enrolled, count: 11 },
                secret_scanning: { status: :enrolled, count: 12 },
              }
            )),
            (@repo_cs_not_enabled = create_repo("#{@org}-cs-not-enabled-repo", owner: @org,
              features: {
                code_scanning: { status: :not_enrolled, count: 0 },
                code_scanning_auto_codeql: { status: :eligible, count: 0 },
              },
            )),
            (@repo_no_features_enabled = create_repo("#{@org}-none-enabled-repo", owner: @org)),
          ]
        end

        setup do
          @base_rel = Repository.joins(:feature_status_summary).all
        end

        context "#apply" do
          test "filters by features with inclusive filters" do
            assert_query_count(1) do
              ByFeature.new(["enabled"], [], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled, @repo_cs_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new(["enabled"], [], feature: "secret_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_ss_enabled, @repo_cs_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new(["not-enabled"], [], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_not_enabled, @repo_ss_enabled, @repo_no_features_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new(["eligible"], [], feature: "code_scanning_auto_codeql").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_not_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new(["eligible"], [], feature: "secret_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = []
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new(["not-eligible"], [], feature: "code_scanning_auto_codeql").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_ss_enabled, @repo_cs_ss_enabled, @repo_no_features_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end
          end

          test "filters by features with exclusive filters" do
            assert_query_count(1) do
              ByFeature.new([], ["enabled"], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_not_enabled, @repo_ss_enabled, @repo_no_features_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new([], ["enabled"], feature: "secret_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled, @repo_cs_not_enabled, @repo_no_features_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new([], ["not-enabled"], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled, @repo_cs_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new([], ["eligible"], feature: "code_scanning_auto_codeql").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = @all_repos - [@repo_cs_not_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new([], ["eligible"], feature: "secret_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = @all_repos - []
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new([], ["not-eligible"], feature: "code_scanning_auto_codeql").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = @all_repos - [@repo_ss_enabled, @repo_cs_ss_enabled, @repo_no_features_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end
          end

          test "filters by features with both inclusive and exclusive filters" do
            assert_query_count(1) do
              ByFeature.new(["enabled"], ["not-enabled"], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled, @repo_cs_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new(["not-enabled"], ["enabled"], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_ss_enabled, @repo_cs_not_enabled, @repo_no_features_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            # Conflicting filters
            assert_query_count(1) do
              ByFeature.new(["enabled"], ["enabled"], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = []
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end
          end

          test "filters by multiple features when applied multiple times with inclusive filters" do
            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByFeature.new(["enabled"], [], feature: "code_scanning_alerts").apply(rel) }
                .then { |rel| ByFeature.new(["enabled"], [], feature: "secret_scanning_alerts").apply(rel) }
                .to_a
            end.tap do |results|
              expected_repos = [@repo_cs_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByFeature.new(["not-enabled"], [], feature: "code_scanning_alerts").apply(rel) }
                .then { |rel| ByFeature.new(["enabled"], [], feature: "secret_scanning_alerts").apply(rel) }
                .to_a
            end.tap do |results|
              expected_repos = [@repo_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByFeature.new(["not-enabled"], [], feature: "code_scanning_alerts").apply(rel) }
                .then { |rel| ByFeature.new(["not-enabled"], [], feature: "secret_scanning_alerts").apply(rel) }
                .to_a
            end.tap do |results|
              expected_repos = [@repo_cs_not_enabled, @repo_no_features_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end
          end

          test "filters by multiple features when applied multiple times with exclusive filters" do
            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByFeature.new([], ["enabled"], feature: "code_scanning_alerts").apply(rel) }
                .then { |rel| ByFeature.new([], ["enabled"], feature: "secret_scanning_alerts").apply(rel) }
                .to_a
            end.tap do |results|
              expected_repos = [@repo_cs_not_enabled, @repo_no_features_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByFeature.new([], ["not-enabled"], feature: "code_scanning_alerts").apply(rel) }
                .then { |rel| ByFeature.new([], ["enabled"], feature: "secret_scanning_alerts").apply(rel) }
                .to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByFeature.new([], ["not-enabled"], feature: "code_scanning_alerts").apply(rel) }
                .then { |rel| ByFeature.new([], ["not-enabled"], feature: "secret_scanning_alerts").apply(rel) }
                .to_a
            end.tap do |results|
              expected_repos = [@repo_cs_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end
          end

          test "filters by multiple features when applied multiple times with both inclusive and exclusive filters" do
            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByFeature.new(["enabled"], [], feature: "code_scanning_alerts").apply(rel) }
                .then { |rel| ByFeature.new([], ["enabled"], feature: "secret_scanning_alerts").apply(rel) }
                .to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled,]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByFeature.new([], ["enabled"], feature: "code_scanning_alerts").apply(rel) }
                .then { |rel| ByFeature.new(["enabled"], [], feature: "secret_scanning_alerts").apply(rel) }
                .to_a
            end.tap do |results|
              expected_repos = [@repo_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end
          end

          test "doesn't filter if no filters are provided" do
            assert_query_count(1) do
              ByFeature.new(nil, nil, feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = @all_repos
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(0) do
              ByFeature.new([], [], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = @all_repos
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end
          end

          test "returns proper result for is_empty?" do
            assert ByFeature.new(nil, nil, feature: "code_scanning_alerts").is_empty?
            assert ByFeature.new([], [], feature: "code_scanning_alerts").is_empty?
            refute ByFeature.new(["enabled"], [], feature: "code_scanning_alerts").is_empty?
            refute ByFeature.new([], ["enabled"], feature: "code_scanning_alerts").is_empty?
          end

          test "filters by unrecognized features" do
            feature = "unrecognized"

            assert_query_count(1) do
              ByFeature.new(["enabled"], [], feature: feature).apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = []
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new(["not-enabled"], [], feature: feature).apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = []
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new([], ["enabled"], feature: feature).apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = []
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new([], ["not-enabled"], feature: feature).apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = []
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end
          end

          test "filters by unrecognized filter values" do
            filter_value = "unrecognized"

            assert_query_count(0) do
              ByFeature.new([filter_value], nil, feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = []
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new([], [filter_value], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = @all_repos
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end
          end

          test "filters by alert counts with inclusive filters" do
            repo_cs_no_alerts = create_repo("#{@org}-cs-no-alerts-repo", owner: @org,
              features: {
                code_scanning: { status: :enrolled, count: 0 },
              }
            )

            assert_query_count(1) do
              ByFeature.new(["0"], [], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_ss_enabled, @repo_cs_not_enabled, @repo_no_features_enabled, repo_cs_no_alerts]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new(["1"], [], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new([">1"], [], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new([">=1"], [], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled, @repo_cs_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new(["<11"], [], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled, @repo_ss_enabled, @repo_cs_not_enabled, @repo_no_features_enabled, repo_cs_no_alerts]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new(["<=11"], [], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled, @repo_ss_enabled, @repo_cs_ss_enabled, @repo_cs_not_enabled, @repo_no_features_enabled, repo_cs_no_alerts]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new([">0", "<10"], [], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = @all_repos + [repo_cs_no_alerts]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end
          end

          test "filters by alert counts with exclusive filters" do
            assert_query_count(1) do
              ByFeature.new([], ["0"], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled, @repo_cs_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              ByFeature.new([], [">10"], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = @all_repos - [@repo_cs_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end
          end

          test "filters by alert counts with both inclusive and exclusive filters" do
            assert_query_count(1) do
              ByFeature.new([">0"], [">10"], feature: "code_scanning_alerts").apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end
          end

          test "filters by alert counts when applied multiple times with multiple inclusive and exclusive filters" do
            repo_cs_ss_no_ss_alerts = create_repo("#{@org}-cs-ss-no-ss-alerts-repo", owner: @org,
              features: {
                code_scanning: { status: :enrolled, count: 2 },
                secret_scanning: { status: :enrolled, count: 0 },
              }
            )

            repo_cs_ss_no_cs_alerts = create_repo("#{@org}-cs-ss-no-cs-alerts-repo", owner: @org,
              features: {
                code_scanning: { status: :enrolled, count: 0 },
                secret_scanning: { status: :enrolled, count: 2 },
              }
            )

            repo_cs_ss_no_alerts = create_repo("#{@org}-cs-ss-no-alerts-repo", owner: @org,
              features: {
                code_scanning: { status: :enrolled, count: 0 },
                secret_scanning: { status: :enrolled, count: 0 },
              }
            )

            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByFeature.new([">0"], [], feature: "code_scanning_alerts").apply(rel) }
                .then { |rel| ByFeature.new([">0"], [], feature: "secret_scanning_alerts").apply(rel) }
                .to_a
            end.tap do |results|
              expected_repos = [@repo_cs_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByFeature.new([">0"], [], feature: "code_scanning_alerts").apply(rel) }
                .then { |rel| ByFeature.new([], [">0"], feature: "secret_scanning_alerts").apply(rel) }
                .to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled, repo_cs_ss_no_ss_alerts]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByFeature.new([], [">0"], feature: "code_scanning_alerts").apply(rel) }
                .then { |rel| ByFeature.new([], [">0"], feature: "secret_scanning_alerts").apply(rel) }
                .to_a
            end.tap do |results|
              expected_repos = [@repo_cs_not_enabled, @repo_no_features_enabled, repo_cs_ss_no_alerts]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByFeature.new([">0"], [], feature: "code_scanning_alerts").apply(rel) }
                .then { |rel| ByFeature.new(["0"], [], feature: "secret_scanning_alerts").apply(rel) }
                .to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled,  repo_cs_ss_no_ss_alerts]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByFeature.new([">0"], [], feature: "code_scanning_alerts").apply(rel) }
                .then { |rel| ByFeature.new([], ["0"], feature: "secret_scanning_alerts").apply(rel) }
                .to_a
            end.tap do |results|
              expected_repos = [@repo_cs_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end

            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByFeature.new([], [">0"], feature: "code_scanning_alerts").apply(rel) }
                .then { |rel| ByFeature.new([], ["0"], feature: "secret_scanning_alerts").apply(rel) }
                .to_a
            end.tap do |results|
              expected_repos = [@repo_ss_enabled, repo_cs_ss_no_cs_alerts]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end
          end
        end

        def create_repo(name, owner:, features: {}, create_statuses_for_unspecified_features: true)
          create(:private_repository, name: name, owner: owner).tap do |r|
            repository_metadata = create(:soa_repository, repository: r)

            create(
              :soa_feature_status,
              repository_metadata:,
              advanced_security_status: "ENABLED",
              dependabot_alerts_status: features.dig(:dependabot_alerts, :status) == :enrolled ? "ENABLED" : "NOT_ENABLED",
              dependabot_alerts_total_count: features.dig(:dependabot_alerts, :count) || 0,
              code_scanning_alerts_status: features.dig(:code_scanning, :status) == :enrolled ? "ENABLED" : "NOT_ENABLED",
              code_scanning_alerts_total_count: features.dig(:code_scanning, :count) || 0,
              secret_scanning_alerts_status: features.dig(:secret_scanning, :status) == :enrolled ? "ENABLED" : "NOT_ENABLED",
              secret_scanning_alerts_total_count: features.dig(:secret_scanning, :count) || 0,
              dependabot_security_updates_status: features.dig(:dependabot_security_updates, :status) == :enrolled ? "ENABLED" : "NOT_ENABLED",
              dependabot_version_updates_status: features.dig(:dependabot_version_updates, :status) == :enrolled ? "ENABLED" : "NOT_ENABLED",
              code_scanning_auto_codeql_status: \
                case features.dig(:code_scanning_auto_codeql, :status)
                when :enrolled; "ENABLED"
                when :eligible; "ELIGIBLE"
                else "NOT_ELIGIBLE"
                end,
              code_scanning_pr_reviews_status: features.dig(:code_scanning_pr_reviews, :status) == :enrolled ? "ENABLED" : "NOT_ENABLED",
              secret_scanning_push_protection_status: features.dig(:secret_scanning_push_protection, :status) == :enrolled ? "ENABLED" : "NOT_ENABLED",
            )
          end
        end
      end
    end
  end
end
