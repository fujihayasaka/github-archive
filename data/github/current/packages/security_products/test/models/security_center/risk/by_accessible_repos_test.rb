# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Risk
    class ByAccessibleReposTest < GitHub::TestCase
      fixtures do
        @org1 = create(:organization, name: "test-org-1").tap do |o|
          @cs_repo = create_repo("#{o}-cs-repo", owner: o, dbot_count: 0, cs_count: 1, ss_count: 0)
          @dbot_repo = create_repo("#{o}-dbot-repo", owner: o, dbot_count: 1, cs_count: 0, ss_count: 0)
          @ss_repo = create_repo("#{o}-ss-repo", owner: o, dbot_count: 0, cs_count: 0, ss_count: 1)
          @mixed_repo = create_repo("#{o}-mixed-repo", owner: o, dbot_count: 1, cs_count: 1, ss_count: 1)
          @no_alerts_repo = create_repo("#{o}-no-alerts-repo", owner: o, dbot_count: 0, cs_count: 0, ss_count: 0)
        end
      end

      setup do
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
        SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(true)
        SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
        SecurityCenter::SecurityFeatures.stubs(:secret_scanning_alerts_enabled_for_instance?).returns(true)

        @rel = RepositorySecurityCenterConfig.all
      end

      test "returns results for all accessible repos if no feature filters are applied" do
        repo_ids_by_feature = {
          dependabot_alerts: [@dbot_repo].map(&:id),
          code_scanning: [@cs_repo].map(&:id),
          secret_scanning: [@ss_repo].map(&:id),
        }

        filter = ByAccessibleRepos.new(parser: new_parser, repo_ids_by_feature: repo_ids_by_feature)
        expected = [@cs_repo, @dbot_repo, @ss_repo]
        assert_same_elements expected.map(&:id), filter.apply(@rel).map(&:repository_id)
      end

      test "returns results for specific feature if filtering by alert count" do
        repo_ids_by_feature = {
          dependabot_alerts: [@dbot_repo].map(&:id),
          code_scanning: [@cs_repo].map(&:id),
          secret_scanning: [@ss_repo].map(&:id),
        }

        filter = ByAccessibleRepos.new(parser: new_parser("code-scanning-alerts:>0"), repo_ids_by_feature: repo_ids_by_feature)
        expected = [@cs_repo]
        assert_same_elements expected.map(&:id), filter.apply(@rel).map(&:repository_id)
      end

      test "returns results for specific feature if filtering by feature enablement" do
        repo_ids_by_feature = {
          dependabot_alerts: [@dbot_repo].map(&:id),
          code_scanning: [@cs_repo].map(&:id),
          secret_scanning: [@ss_repo].map(&:id),
        }

        filter = ByAccessibleRepos.new(parser: new_parser("code-scanning-alerts:enabled"), repo_ids_by_feature: repo_ids_by_feature)
        expected = [@cs_repo]
        assert_same_elements expected.map(&:id), filter.apply(@rel).map(&:repository_id)
      end

      test "returns results for all accessible repos if filter excludes feature enablement" do
        repo_ids_by_feature = {
          dependabot_alerts: [@dbot_repo].map(&:id),
          code_scanning: [@cs_repo].map(&:id),
          secret_scanning: [@ss_repo].map(&:id),
        }

        filter = ByAccessibleRepos.new(parser: new_parser("-code-scanning-alerts:enabled"), repo_ids_by_feature: repo_ids_by_feature)
        expected = [@cs_repo, @dbot_repo, @ss_repo]
        assert_same_elements expected.map(&:id), filter.apply(@rel).map(&:repository_id)
      end

      test "returns results for intersection of repos when filtering by multiple features" do
        repo_ids_by_feature = {
          dependabot_alerts: [@dbot_repo, @mixed_repo].map(&:id),
          code_scanning: [@cs_repo, @mixed_repo].map(&:id),
          secret_scanning: [@ss_repo, @mixed_repo].map(&:id),
        }

        filter = ByAccessibleRepos.new(parser: new_parser("code-scanning-alerts:enabled dependabot-alerts:>0"), repo_ids_by_feature: repo_ids_by_feature)
        expected = [@mixed_repo]
        assert_same_elements expected.map(&:id), filter.apply(@rel).map(&:repository_id)
      end

      test "returns results when filtered by feature enablement no repo access for that feature" do
        repo_ids_by_feature = {
          dependabot_alerts: [@dbot_repo].map(&:id),
          code_scanning: nil,
        }

        filter = ByAccessibleRepos.new(parser: new_parser("code-scanning-alerts:enabled"), repo_ids_by_feature: repo_ids_by_feature)
        expected = [@dbot_repo]
        assert_same_elements expected.map(&:id), filter.apply(@rel).map(&:repository_id)
      end

      private

      def new_parser(query_string = "")
        ::Search::Queries::SecurityCenter::RiskQueryParser.new(query_string)
      end

      def create_repo(name, owner:,  dbot_count: 0, cs_count: 0, ss_count: 0)
        create(:private_repository, name: name, owner: owner).tap do |r|
          create(:repository_security_center_config, repository: r)
          create_status(r, feature: :dependabot_alerts, count: dbot_count)
          create_status(r, feature: :code_scanning, count: cs_count)
          create_status(r, feature: :secret_scanning, count: ss_count)
        end
      end

      def create_status(repo, feature:, count:)
        create(
          :repository_security_center_status,
          feature,
          count > 0 ? :enrolled : :not_enrolled,
          scanning_count: count,
          repository: repo,
        )
      end
    end
  end
end
