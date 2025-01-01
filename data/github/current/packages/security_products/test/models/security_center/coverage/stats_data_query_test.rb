# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Coverage
    class CoverageStatsDataQueryTest < GitHub::TestCase
      fixtures do
        # Business
        GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
        @owner = create(:user)
        @user_session = create(:user_session, user: @owner)
        @business = create(:global_business)
        @business.add_owner(@owner, actor: nil)

        # Orgs and repos
        @org1 = create(:business_plus_organization, business: @business, admin: @owner, name: "test-org-1").tap do |o|
          @cs_repo = create_repo("#{o}-cs-repo", owner: o, enabled_features: [:code_scanning, :code_scanning_pr_reviews])
          @dbot_repo = create_repo("#{o}-dbot-repo", owner: o, enabled_features: [:dependabot_alerts, :dependabot_security_updates])
          @ss_repo = create_repo("#{o}-ss-repo", owner: o, enabled_features: [:secret_scanning, :secret_scanning_push_protection])
          @mixed_repo = create_repo("#{o}-mixed-repo", owner: o, enabled_features: [:code_scanning, :dependabot_alerts, :secret_scanning])
          @missing_statuses_repo = create_repo("#{o}-missing-statuses-repo", owner: o, skip_creating_not_enrolled_statuses: true)
          @user_ss_repo = create_repo("#{o}-user-ss-repo", owner: @owner, enabled_features: [:secret_scanning])
          @user_clear_repo = create_repo("#{o}-user-clear-repo", owner: @owner, enabled_features: [])

          create(:team, name: "#{o}-mixed-repo-team", organization: o).tap { |team| team.add_repository(@mixed_repo, :admin) }

          create(:topic, name: "apples").tap { |t| create(:repository_topic, topic: t, repository: @cs_repo) }
          create(:topic, name: "oranges").tap { |t| create(:repository_topic, topic: t, repository: @dbot_repo) }

          @org1_owner = create(:user).tap do |u|
            o.add_admin(u)
          end
        end

        @org2 = create(:business_plus_organization, business: @business, name: "test-org-2")

        unless GitHub.enterprise?
          @mt_user = create(:emu)
          @mt_biz = @mt_user.enterprise_managed_business
          @mt_owner = @mt_biz.find_first_emu_owner
          @mt_owner_session = create(:user_session, user: @mt_owner)

          @mt_user.tap do |o|
            @mt_user_ss_repo = create_repo("#{o}-ss-repo", owner: o, enabled_features: [:secret_scanning])
            @mt_user_clear_repo = create_repo("#{o}-clear-repo", owner: o, enabled_features: [])
          end

          @mt_org = create(:business_plus_organization, business: @mt_biz, admin: @mt_user, name: "mt-org").tap do |o|
            create_repo("#{o}-cs-repo", owner: o, enabled_features: [:code_scanning, :code_scanning_pr_reviews])
            create_repo("#{o}-multi-repo", owner: o, enabled_features: [:code_scanning, :secret_scanning])
          end

          enterprise_security_manager_team = create :enterprise_security_manager_team, business: @mt_biz
          @enterprise_security_manager = create :emu
          @mt_org.add_member @enterprise_security_manager # Because the factory doesn't set up the org teams sync
          enterprise_security_manager_team.bulk_add_members(users: [@enterprise_security_manager])
        end
      end

      setup do
        Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

        SecurityCenter::SecurityFeatures.stubs(
          code_scanning_enabled_for_instance?: true,
          secret_scanning_enabled_for_instance?: true,
          dependabot_alerts_enabled_for_instance?: true,
        )
        SecurityCenter::Filters::ByCustomProperty.any_instance.stubs(:es_repo_ids).returns(@org1.repositories.pluck(:id))

        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
      end

      # Returns an array of 2-tuples of the form [[pos_filter, neg_filter], expected_query_count]
      def self.basic_filters_and_sort_with_query_counts
        # Author these to always match at least one repo so we can evaluate how many queries are made.
        [
          ["unqualified term", "cs-repo", 1],
          ["owner name", "owner:test-org-1", 4],
          ["owner type", "owner-type:organization", 4],
          ["repository name", "repo:test-org-1-cs-repo", 1],
          ["visibility", "is:internal", 0],
          ["archived", "archived:true", 0],
          ["team", "team:test-org-1-mixed-repo-team", 1],
          ["topic", "topic:apples", 1],
          ["advanced-security", "advanced-security:enabled", 4],
          ["dependabot-alerts", "dependabot-alerts:enabled", 2],
          ["dependabot-security-updates", "dependabot-security-updates:enabled", 1],
          ["code-scanning-alerts", "code-scanning-alerts:enabled", 2],
          ["code-scanning-pull-request-alerts", "code-scanning-pull-request-alerts:enabled", 1],
          ["code-scanning-default-setup", "code-scanning-default-setup:eligible", 0],
          ["secret-scanning", "secret-scanning-alerts:enabled", 2],
          ["secret-scanning-push-protection", "secret-scanning-push-protection:enabled", 1],
          ["sort", "sort:last-updated-asc", 4],
          ["custom-properties", "props.custom:property", 4],
        ]
      end

      context "#run" do
        context "for businesses with enterprise managed users on dotcom", skip_enterprise: true do
          test "includes EMU-owned repos" do
            result = StatsDataQuery.for_organizations(user: @mt_owner, user_session: @mt_owner_session, business: @mt_biz, organizations: [@mt_org], parser: new_parser("")).run

            assert_stats_structure result

            assert_eligible_repo_count result, 4

            assert_feature_enabled_count result, 0, :dependabot_alerts
            assert_feature_enabled_count result, 0, :dependabot_security_updates
            assert_feature_enabled_count result, 2, :code_scanning
            assert_feature_enabled_count result, 1, :code_scanning_pr_reviews
            assert_feature_enabled_count result, 0, :code_scanning_auto_codeql
            assert_feature_enabled_count result, 2, :secret_scanning
            assert_feature_enabled_count result, 0, :secret_scanning_push_protection
          end

          test "includes EMU-owned repos if user is an enterprise security manager" do
            result = StatsDataQuery.for_organizations(user: @enterprise_security_manager, user_session: @mt_owner_session, business: @mt_biz, organizations: [@mt_org], parser: new_parser("")).run

            assert_stats_structure result

            assert_eligible_repo_count result, 4

            assert_feature_enabled_count result, 0, :dependabot_alerts
            assert_feature_enabled_count result, 0, :dependabot_security_updates
            assert_feature_enabled_count result, 2, :code_scanning
            assert_feature_enabled_count result, 1, :code_scanning_pr_reviews
            assert_feature_enabled_count result, 0, :code_scanning_auto_codeql
            assert_feature_enabled_count result, 2, :secret_scanning
            assert_feature_enabled_count result, 0, :secret_scanning_push_protection
          end


          test "excludes EMU-owned repos if user is not an owner of the business" do
            user_session = create(:user_session, user: @mt_user)
            result = StatsDataQuery.for_organizations(user: @mt_user, user_session: user_session, business: @mt_biz, organizations: [@mt_org], parser: new_parser("")).run

            assert_stats_structure result

            # Only results for @mt_org
            assert_eligible_repo_count result, 2

            assert_feature_enabled_count result, 0, :dependabot_alerts
            assert_feature_enabled_count result, 0, :dependabot_security_updates
            assert_feature_enabled_count result, 2, :code_scanning
            assert_feature_enabled_count result, 1, :code_scanning_pr_reviews
            assert_feature_enabled_count result, 0, :code_scanning_auto_codeql
            assert_feature_enabled_count result, 1, :secret_scanning
            assert_feature_enabled_count result, 0, :secret_scanning_push_protection
          end

          test "excludes EMU-owned repos if GHAS is not purchased" do
            Business.any_instance.stubs(:advanced_security_purchased?).returns(false)

            result = StatsDataQuery.for_organizations(user: @mt_user, user_session: @user_session, business: @mt_biz, organizations: [@mt_org], parser: new_parser("")).run

            assert_stats_structure result

            assert_eligible_repo_count result, 2

            assert_feature_enabled_count result, 0, :dependabot_alerts
            assert_feature_enabled_count result, 0, :dependabot_security_updates
            assert_feature_enabled_count result, 2, :code_scanning
            assert_feature_enabled_count result, 1, :code_scanning_pr_reviews
            assert_feature_enabled_count result, 0, :code_scanning_auto_codeql
            assert_feature_enabled_count result, 1, :secret_scanning
            assert_feature_enabled_count result, 0, :secret_scanning_push_protection
          end
        end

        context "for businesses without enterprise managed users on Dotcom", skip_enterprise: true do
          test "does not include user-owned repos" do
            result = StatsDataQuery.for_organizations(user: @owner, user_session: @user_session, business: @business, organizations: [@org1], parser: new_parser("")).run

            assert_stats_structure result

            assert_eligible_repo_count result, 4

            assert_feature_enabled_count result, 2, :dependabot_alerts
            assert_feature_enabled_count result, 1, :dependabot_security_updates
            assert_feature_enabled_count result, 2, :code_scanning
            assert_feature_enabled_count result, 1, :code_scanning_pr_reviews
            assert_feature_enabled_count result, 0, :code_scanning_auto_codeql
            assert_feature_enabled_count result, 2, :secret_scanning
            assert_feature_enabled_count result, 1, :secret_scanning_push_protection
          end
        end

        context "for businesses with user-owned repositories on GHES", enterprise_only: true do
          test "includes user-owned repos if feature flag is enabled" do
            GitHub.stubs(:security_center_for_emus_enabled?).returns(true)

            result = StatsDataQuery.for_organizations(user: @owner, user_session: @user_session, business: @business, organizations: [@org1], parser: new_parser("")).run

            assert_stats_structure result

            assert_eligible_repo_count result, 6

            assert_feature_enabled_count result, 2, :dependabot_alerts
            assert_feature_enabled_count result, 1, :dependabot_security_updates
            assert_feature_enabled_count result, 2, :code_scanning
            assert_feature_enabled_count result, 1, :code_scanning_pr_reviews
            assert_feature_enabled_count result, 0, :code_scanning_auto_codeql
            assert_feature_enabled_count result, 3, :secret_scanning
            assert_feature_enabled_count result, 1, :secret_scanning_push_protection
          end

          test "excludes user-owned repos if GHAS is not purchased" do
            GitHub.stubs(:security_center_for_emus_enabled?).returns(true)
            Business.any_instance.stubs(:advanced_security_purchased?).returns(false)

            result = StatsDataQuery.for_organizations(user: @owner, user_session: @user_session, business: @business, organizations: [@org1], parser: new_parser("")).run

            assert_equal 1, result.length # limited security center, only dependabot alerts visible

            assert_eligible_repo_count result, 4

            assert_feature_enabled_count result, 2, :dependabot_alerts
            assert_feature_enabled_count result, 1, :dependabot_security_updates
          end

          test "excludes user-owned repos if feature flag is disabled" do
            GitHub.stubs(:security_center_for_emus_enabled?).returns(false)

            result = StatsDataQuery.for_organizations(user: @owner, user_session: @user_session, business: @business, organizations: [@org1], parser: new_parser("")).run

            assert_stats_structure result

            assert_eligible_repo_count result, 4

            assert_feature_enabled_count result, 2, :dependabot_alerts
            assert_feature_enabled_count result, 1, :dependabot_security_updates
            assert_feature_enabled_count result, 2, :code_scanning
            assert_feature_enabled_count result, 1, :code_scanning_pr_reviews
            assert_feature_enabled_count result, 0, :code_scanning_auto_codeql
            assert_feature_enabled_count result, 2, :secret_scanning
            assert_feature_enabled_count result, 1, :secret_scanning_push_protection
          end
        end

        test "returns data for unfiltered org query" do
          result = new_query.run

          assert_stats_structure result

          assert_eligible_repo_count result, 4 # 5 repos, one without any status records (missing data edge case)

          assert_feature_enabled_count result, 2, :dependabot_alerts
          assert_feature_enabled_count result, 1, :dependabot_security_updates
          assert_feature_enabled_count result, 2, :code_scanning
          assert_feature_enabled_count result, 1, :code_scanning_pr_reviews
          assert_feature_enabled_count result, 0, :code_scanning_auto_codeql
          assert_feature_enabled_count result, 2, :secret_scanning
          assert_feature_enabled_count result, 1, :secret_scanning_push_protection
        end

        test "returns full structure for empty org" do
          result = new_query(organization: @org2).run

          assert_stats_structure result

          # empty org has 0/0 coverage
          result.each do |stat|
            assert_equal 0, stat.enabled_count
            assert_equal 0, stat.total_count

            stat.subfeature_stats.each do |subfeature|
              assert_equal 0, subfeature.enabled_count
              assert_equal 0, subfeature.total_count
            end
          end
        end

        test "returns results limited by provided repository ids" do
          # no filter
          expected = [@cs_repo, @dbot_repo, @ss_repo, @mixed_repo]
          StatsDataQuery.for_organization(user: @org1_owner, user_session: @user_session, organization: @org1, repo_ids: nil, parser: new_parser).run.tap do |result|
            assert_stats_structure result
            assert_eligible_repo_count result, expected.length
          end

          # partial filter
          expected = [@cs_repo, @dbot_repo, @ss_repo]
          StatsDataQuery.for_organization(user: @org1_owner, user_session: @user_session, organization: @org1, repo_ids: expected.map(&:id), parser: new_parser).run.tap do |result|
            assert_stats_structure result
            assert_eligible_repo_count result, expected.length
          end

          # all filter
          expected = []
          StatsDataQuery.for_organization(user: @org1_owner, user_session: @user_session, organization: @org1, repo_ids: expected.map(&:id), parser: new_parser).run.tap do |result|
            assert_stats_structure result
            assert_eligible_repo_count result, expected.length
          end
        end

        test "executes expected number of queries" do
          assert_query_count(2) do
            new_query.run
          end
        end

        test "only returns data for security features enabled for the instance" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          assert_query_count(2) do
            assert_equal [:dependabot_alerts, :code_scanning, :secret_scanning], new_query.run.map(&:feature_type)
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: false,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          assert_query_count(1) do
            assert_equal [:dependabot_alerts, :secret_scanning], new_query.run.map(&:feature_type)
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: false,
            dependabot_alerts_enabled_for_instance?: true,
          )

          assert_query_count(1) do
            assert_equal [:dependabot_alerts, :code_scanning], new_query.run.map(&:feature_type)
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: false,
          )

          assert_query_count(1) do
            assert_equal [:code_scanning, :secret_scanning], new_query.run.map(&:feature_type)
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: false,
            secret_scanning_enabled_for_instance?: false,
            dependabot_alerts_enabled_for_instance?: false,
          )

          assert_query_count(0) do
            assert_empty new_query.run
          end
        end

        context "filters" do
          basic_filters_and_sort_with_query_counts.each do |test_name, query_string, expected_eligible_count|
            test "by #{test_name}" do
              result = new_query(query_string: query_string).run

              assert_stats_structure result
              assert_eligible_repo_count result, expected_eligible_count
            end
          end

          test "basic test exercising all filters at once" do
            all_filters = self.class.basic_filters_and_sort_with_query_counts.map(&:second).flatten.join(" ")

            # FIXME: should this be in a test for ::Search::Queries::SecurityCenter::CoverageQueryParser ?
            # Make sure we're using all qualifiers, plus unqualified text
            assert_equal StatsDataQuery::CoverageQueryParser::QUALIFIERS.size + 1, self.class.basic_filters_and_sort_with_query_counts.size

            assert_nothing_raised do
              result = new_query(query_string: all_filters).run
              assert_stats_structure result
            end
          end
        end
      end

      private

      def new_query(user: @org1_owner, organization: @org1, query_string: "")
        StatsDataQuery.for_organization(user: user, user_session: @user_session, organization: organization, parser: new_parser(query_string))
      end

      def new_parser(query_string = "")
        ::Search::Queries::SecurityCenter::CoverageQueryParser.new(query_string)
      end

      def create_repo(name, owner:, enabled_features: [], skip_creating_not_enrolled_statuses: false)
        args = {}
        if owner.user?
          args[:force_user_owned] = true
        end
        create(:private_repository, name: name, owner: owner, **args).tap do |r|
          create(
            :repository_security_center_config,
            repository: r,
            ghas_enabled: true,
          )

          all_feature_types = RepositorySecurityCenterStatus.primary_feature_types.flat_map do |primary_type|
            [primary_type] + RepositorySecurityCenterStatus.subfeatures_for(primary_type)
          end

          enabled_features.each do |feature|
            raise "Unknown feature type #{feature}" unless all_feature_types.include?(feature)
            create_status(r, feature: feature, enrolled: true)
          end

          unless skip_creating_not_enrolled_statuses
            (all_feature_types - enabled_features).each do |feature|
              create_status(r, feature: feature, enrolled: false)
            end
          end
        end
      end

      def create_status(repo, feature:, enrolled:)
        create(
          :repository_security_center_status,
          feature,
          enrolled ? :enrolled : :not_enrolled,
          scanning_count: 0,
          repository: repo,
        )
      end

      def assert_stats_structure(result)
        assert_equal 3, result.length

        result[0].tap do |r|
          assert_equal :dependabot_alerts, r.feature_type
          assert_equal 1, r.subfeature_stats.size

          assert_equal :dependabot_security_updates, r.subfeature_stats[0].feature_type
          assert_empty r.subfeature_stats[0].subfeature_stats
        end

        result[1].tap do |r|
          assert_equal :code_scanning, r.feature_type
          assert_equal 2, r.subfeature_stats.size

          assert_equal :code_scanning_pr_reviews, r.subfeature_stats[0].feature_type
          assert_empty r.subfeature_stats[0].subfeature_stats

          assert_equal :code_scanning_auto_codeql, r.subfeature_stats[1].feature_type
          assert_empty r.subfeature_stats[0].subfeature_stats
        end

        result[2].tap do |r|
          assert_equal :secret_scanning, r.feature_type
          assert_equal 1, r.subfeature_stats.size

          assert_equal :secret_scanning_push_protection, r.subfeature_stats[0].feature_type
          assert_empty r.subfeature_stats[0].subfeature_stats
        end
      end

      def assert_eligible_repo_count(result, expected)
        # eligible count is the same across all features/coverages
        result.each do |stat|
          assert_equal expected, stat.total_count

          stat.subfeature_stats.each { |subfeature_stat| assert_equal expected, subfeature_stat.total_count }
        end
      end

      def assert_feature_enabled_count(result, expected_count, feature)
        assert_equal expected_count, result[0].enabled_count if feature == :dependabot_alerts
        assert_equal expected_count, result[0].subfeature_stats[0].enabled_count if feature == :dependabot_security_updates

        assert_equal expected_count, result[1].enabled_count if feature == :code_scanning
        assert_equal expected_count, result[1].subfeature_stats[0].enabled_count if feature == :code_scanning_pr_reviews

        assert_equal expected_count, result[2].enabled_count if feature == :secret_scanning
        assert_equal expected_count, result[2].subfeature_stats[0].enabled_count if feature == :secret_scanning_push_protection
      end
    end
  end
end
