# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Filters
    class ByFeatureTest < GitHub::TestCase
      fixtures do
        @biz = create(:business)
        @org = create(:organization, business: @biz)

        @all_repos = [
          (@repo_cs_enabled = create_repo("#{@org}-cs-enabled-repo", owner: @org,
            features: {
              code_scanning: { status: :enrolled },
              code_scanning_auto_codeql: { status: :enrolled },
            }
          )),
          (@repo_ss_enabled = create_repo("#{@org}-ss-enabled-repo", owner: @org,
            features: {
              secret_scanning: { status: :enrolled },
            }
          )),
          (@repo_cs_ss_enabled = create_repo("#{@org}-cs-ss-enabled-repo", owner: @org,
            features: {
              code_scanning: { status: :enrolled },
              secret_scanning: { status: :enrolled },
            }
          )),
          (@repo_cs_not_enabled = create_repo("#{@org}-cs-not-enabled-repo", owner: @org,
            features: {
              code_scanning: { status: :not_enrolled },
              code_scanning_auto_codeql: { status: :eligible },
            },
          )),
          (@repo_no_features_enabled = create_repo("#{@org}-none-enabled-repo", owner: @org)),
          (@repo_missing_statuses = create_repo("#{@org}-missing-statuses-repo", owner: @org,
            features: {
              secret_scanning: { status: :enrolled },
              code_scanning: { status: :not_enrolled },
              code_scanning_auto_codeql: { status: :not_eligible },
            },
            create_statuses_for_unspecified_features: false)),
          (@repo_no_statuses = create_repo("#{@org}-no-statuses-repo", owner: @org,
            create_statuses_for_unspecified_features: false
          )),
        ]
      end

      setup do
        @base_rel = RepositorySecurityCenterConfig.all
      end

      context "#apply" do
        test "filters by features with inclusive filters" do
          assert_query_count(1) do
            ByFeature.new(["enabled"], [], feature: "code_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@repo_cs_enabled, @repo_cs_ss_enabled]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new(["enabled"], [], feature: "secret_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@repo_ss_enabled, @repo_cs_ss_enabled, @repo_missing_statuses]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new(["not-enabled"], [], feature: "code_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@repo_cs_not_enabled, @repo_ss_enabled, @repo_no_features_enabled, @repo_missing_statuses]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new(["eligible"], [], feature: "code_scanning_auto_codeql", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@repo_cs_not_enabled]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new(["eligible"], [], feature: "secret_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = []
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new(["not-eligible"], [], feature: "code_scanning_auto_codeql", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@repo_missing_statuses]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "filters by features with exclusive filters" do
          assert_query_count(1) do
            ByFeature.new([], ["enabled"], feature: "code_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@repo_cs_not_enabled, @repo_ss_enabled, @repo_no_features_enabled, @repo_missing_statuses]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new([], ["enabled"], feature: "secret_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@repo_cs_enabled, @repo_cs_not_enabled, @repo_no_features_enabled]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new([], ["not-enabled"], feature: "code_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@repo_cs_enabled, @repo_cs_ss_enabled]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new([], ["eligible"], feature: "code_scanning_auto_codeql", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @all_repos - [@repo_cs_not_enabled, @repo_no_statuses]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new([], ["eligible"], feature: "secret_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @all_repos - [@repo_no_statuses]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new([], ["not-eligible"], feature: "code_scanning_auto_codeql", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @all_repos - [@repo_missing_statuses, @repo_no_statuses]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "filters by features with both inclusive and exclusive filters" do
          assert_query_count(1) do
            ByFeature.new(["enabled"], ["not-enabled"], feature: "code_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@repo_cs_enabled, @repo_cs_ss_enabled]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new(["not-enabled"], ["enabled"], feature: "code_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = [@repo_ss_enabled, @repo_cs_not_enabled, @repo_no_features_enabled, @repo_missing_statuses]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          # Conflicting filters
          assert_query_count(1) do
            ByFeature.new(["enabled"], ["enabled"], feature: "code_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = []
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "filters by multiple features when applied multiple times with inclusive filters" do
          assert_query_count(1) do
            @base_rel \
              .then { |rel| ByFeature.new(["enabled"], [], feature: "code_scanning", scope: @org).apply(rel) }
              .then { |rel| ByFeature.new(["enabled"], [], feature: "secret_scanning", scope: @org).apply(rel) }
              .to_a
          end.tap do |results|
            expected_repos = [@repo_cs_ss_enabled]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            @base_rel \
              .then { |rel| ByFeature.new(["not-enabled"], [], feature: "code_scanning", scope: @org).apply(rel) }
              .then { |rel| ByFeature.new(["enabled"], [], feature: "secret_scanning", scope: @org).apply(rel) }
              .to_a
          end.tap do |results|
            expected_repos = [@repo_ss_enabled, @repo_missing_statuses]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            @base_rel \
              .then { |rel| ByFeature.new(["not-enabled"], [], feature: "code_scanning", scope: @org).apply(rel) }
              .then { |rel| ByFeature.new(["not-enabled"], [], feature: "secret_scanning", scope: @org).apply(rel) }
              .to_a
          end.tap do |results|
            expected_repos = [@repo_cs_not_enabled, @repo_no_features_enabled]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "filters by multiple features when applied multiple times with exclusive filters" do
          assert_query_count(1) do
            @base_rel \
              .then { |rel| ByFeature.new([], ["enabled"], feature: "code_scanning", scope: @org).apply(rel) }
              .then { |rel| ByFeature.new([], ["enabled"], feature: "secret_scanning", scope: @org).apply(rel) }
              .to_a
          end.tap do |results|
            expected_repos = [@repo_cs_not_enabled, @repo_no_features_enabled]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            @base_rel \
              .then { |rel| ByFeature.new([], ["not-enabled"], feature: "code_scanning", scope: @org).apply(rel) }
              .then { |rel| ByFeature.new([], ["enabled"], feature: "secret_scanning", scope: @org).apply(rel) }
              .to_a
          end.tap do |results|
            expected_repos = [@repo_cs_enabled]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            @base_rel \
              .then { |rel| ByFeature.new([], ["not-enabled"], feature: "code_scanning", scope: @org).apply(rel) }
              .then { |rel| ByFeature.new([], ["not-enabled"], feature: "secret_scanning", scope: @org).apply(rel) }
              .to_a
          end.tap do |results|
            expected_repos = [@repo_cs_ss_enabled]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "filters by multiple features when applied multiple times with both inclusive and exclusive filters" do
          assert_query_count(1) do
            @base_rel \
              .then { |rel| ByFeature.new(["enabled"], [], feature: "code_scanning", scope: @org).apply(rel) }
              .then { |rel| ByFeature.new([], ["enabled"], feature: "secret_scanning", scope: @org).apply(rel) }
              .to_a
          end.tap do |results|
            expected_repos = [@repo_cs_enabled,]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            @base_rel \
              .then { |rel| ByFeature.new([], ["enabled"], feature: "code_scanning", scope: @org).apply(rel) }
              .then { |rel| ByFeature.new(["enabled"], [], feature: "secret_scanning", scope: @org).apply(rel) }
              .to_a
          end.tap do |results|
            expected_repos = [@repo_ss_enabled, @repo_missing_statuses]
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "doesn't filter if no filters are provided" do
          assert_query_count(1) do
            ByFeature.new(nil, nil, feature: "code_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @all_repos
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(0) do
            ByFeature.new([], [], feature: "code_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @all_repos
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "returns proper result for is_empty?" do
          assert ByFeature.new(nil, nil, feature: "code_scanning", scope: @org).is_empty?
          assert ByFeature.new([], [], feature: "code_scanning", scope: @org).is_empty?
          refute ByFeature.new(["enabled"], [], feature: "code_scanning", scope: @org).is_empty?
          refute ByFeature.new([], ["enabled"], feature: "code_scanning", scope: @org).is_empty?
        end

        test "filters by unrecognized features" do
          feature = "unrecognized"

          assert_query_count(1) do
            ByFeature.new(["enabled"], [], feature: feature, scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = []
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new(["not-enabled"], [], feature: feature, scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = []
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new([], ["enabled"], feature: feature, scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = []
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new([], ["not-enabled"], feature: feature, scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = []
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "filters by unrecognized filter values" do
          filter_value = "unrecognized"

          assert_query_count(0) do
            ByFeature.new([filter_value], nil, feature: "code_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = []
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByFeature.new([], [filter_value], feature: "code_scanning", scope: @org).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @all_repos
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        context "scopes to the business" do
          test "with an empty business", skip_enterprise: true do
            other_biz = create(:business)

            assert_query_count(1) do
              ByFeature.new(["enabled"], [], feature: "code_scanning", scope: other_biz).apply(@base_rel).to_a
            end.tap do |results|
              assert_empty results
            end
          end

          test "with a business that has orgs with repos" do
            assert_query_count(1) do
              ByFeature.new(["enabled"], [], feature: "code_scanning", scope: @biz).apply(@base_rel).to_a
            end.tap do |results|
              expected_repos = [@repo_cs_enabled, @repo_cs_ss_enabled]
              assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
            end
          end
        end
      end

      def create_repo(name, owner:, features: {}, create_statuses_for_unspecified_features: true)
        create(:private_repository, name: name, owner: owner).tap do |r|
          create(
            :repository_security_center_config,
            repository: r,
            ghas_enabled: true,
          )

          all_feature_types = RepositorySecurityCenterStatus.primary_feature_types.flat_map do |primary_type|
            [primary_type] + RepositorySecurityCenterStatus.subfeatures_for(primary_type)
          end

          features.each do |feature, opts|
            opts => { status: }
            raise "Unknown feature type #{feature}" unless all_feature_types.include?(feature)
            create_status(r, feature: feature, status: status)
          end

          if create_statuses_for_unspecified_features
            (all_feature_types - features.keys).each do |feature|
              create_status(r, feature: feature, status: :not_enrolled)
            end
          end
        end
      end

      def create_status(repo, feature:, status:)
        create(
          :repository_security_center_status,
          feature,
          scanning_status: status,
          repository: repo,
        )
      end
    end
  end
end
