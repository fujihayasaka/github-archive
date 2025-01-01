# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Risk
    class StatsQueryTest < GitHub::TestCase
      fixtures do
        # Business
        GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
        @owner = create(:user)
        @user_session = create(:user_session, user: @owner)
        @business = create(:global_business)

        # Orgs and repos
        @org1 = create(:business_plus_organization, business: @business, admin: @owner, name: "test-org-1").tap do |o|
          @dbot_repo = create_repo("#{o}-dbot-repo", owner: o,
            dbot_counts: { critical: 3, high: 2, moderate: 1, low: 1 })
          @cs_repo = create_repo("#{o}-cs-repo", owner: o,
            cs_counts: { critical: 1, high: 2, medium: 3, low: 4, error: 5, warning: 6, note: 7 })
          @ss_repo = create_repo("#{o}-ss-repo", owner: o, ss_counts: { critical: 3 })
          @mixed_repo = create_repo("#{o}-mixed-repo", owner: o,
            dbot_counts: { critical: 1 },
            cs_counts: { medium: 1 })
          @clear_repo = create_repo("#{o}-clear-repo", owner: o)
          @user_ss_repo = create_repo("#{o}-user-ss-repo", owner: @owner, ss_counts: { critical: 3 })
          @user_clear_repo = create_repo("#{o}-user-clear-repo", owner: @owner)

          # add team/topic relationships to validate filters
          # which repository we use here isn't relevant; we just need the filters to match one during tests
          create(:team, name: "banana", organization: o).tap { |team| team.add_repository(@ss_repo, :admin) }
          create(:topic, name: "apples").tap { |t| create(:repository_topic, topic: t, repository: @dbot_repo) }
          create(:topic, name: "oranges").tap { |t| create(:repository_topic, topic: t, repository: @cs_repo) }

          @org1_owner = create(:user).tap do |u|
            o.add_admin(u)
            @business.add_owner(u, actor: nil)
          end
        end

        @org2 = create(:business_plus_organization, business: @business, name: "test-org-2")

        unless GitHub.enterprise?
          @mt_biz = create(:business, :enterprise_managed, shortcode: "mtbiz", slug: "mtbusiness")
          @mt_user = create(:emu, login: "mt-user", business: @mt_biz)
          @mt_owner = @mt_biz.find_first_emu_owner

          @mt_user.tap do |o|
            @mt_user_ss1_repo = create_repo("#{o}-ss1-repo", owner: o, ss_counts: { critical: 1 })
            @mt_user_ss2_repo = create_repo("#{o}-ss2-repo", owner: o, ss_counts: { critical: 2 })
            @mt_user_ss3_repo = create_repo("#{o}-ss3-repo", owner: o, ss_counts: { critical: 3 })
            @mt_user_clear_repo = create_repo("#{o}-clear-repo", owner: o)
          end

          @mt_org = create(:business_plus_organization, admin: @owner, business: @mt_biz, name: "test-org-emu").tap do |o|
            @mt_org_clear_repo = create_repo("#{o}-clear-repo", owner: o)
            @mt_org_ss4_repo = create_repo("#{o}-ss4-repo", owner: o, ss_counts: { critical: 4 })
          end

          enterprise_security_manager_team = create :enterprise_security_manager_team, business: @mt_biz
          @enterprise_security_manager = create :user
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

      context "#run" do
        test "returns data for unfiltered org query" do
          result = new_query.perform

          assert_stats_structure result

          # Dependabot alerts
          assert_equal 2, result.items[0].stats_data[0].items[0].count # affected_repo_count
          assert_equal 8, result.items[0].stats_data[1].count # open_alerts_count
          assert_equal 5, result.items[0].stats_data[0].count # total_repo_count
          assert_equal %w[critical high moderate low], result.items[0].stats_data[1].items.map(&:name)
          assert_equal 4, result.items[0].stats_data[1].items[0].count
          assert_equal 2, result.items[0].stats_data[1].items[1].count
          assert_equal 1, result.items[0].stats_data[1].items[2].count
          assert_equal 1, result.items[0].stats_data[1].items[3].count

          # Code Scanning alerts
          assert_equal 2, result.items[1].stats_data[0].items[0].count # affected_repo_count
          assert_equal 29, result.items[1].stats_data[1].count # open_alerts_count
          assert_equal 5, result.items[1].stats_data[0].count # total_repo_count
          assert_equal %w[critical high medium low informational], result.items[1].stats_data[1].items.map(&:name)
          assert_equal 1, result.items[1].stats_data[1].items[0].count
          assert_equal 2, result.items[1].stats_data[1].items[1].count
          assert_equal 4, result.items[1].stats_data[1].items[2].count
          assert_equal 4, result.items[1].stats_data[1].items[3].count
          assert_equal 18, result.items[1].stats_data[1].items[4].count

          # Secret Scanning alerts
          assert_equal 1, result.items[2].stats_data[0].items[0].count # affected_repo_count
          assert_equal 3, result.items[2].stats_data[1].count # open_alerts_count
          assert_equal 5, result.items[2].stats_data[0].count # total_repo_count
          assert_equal %w[alerts], result.items[2].stats_data[1].items.map(&:name)
          assert_equal 3, result.items[2].stats_data[1].items[0].count
        end

        test "returns nothing when there is a mismatch in the business and organizations", skip_enterprise: true do
          enable_feature_flag(:security_center_include_biz_on_status_queries)

          other_emu = create(:emu)
          other_biz = other_emu.enterprise_managed_business

          # The business, passed in via scope, does not own anything inside organizations
          # so we should get 0 records
          result = new_query(scope: other_biz, organizations: [@mt_org]).perform

          assert_stats_structure result

          # Dependabot alerts
          assert_equal 0, result.items[0].stats_data[0].items[0].count # affected_repo_count
          assert_equal 0, result.items[0].stats_data[1].count # open_alerts_count
          assert_equal 0, result.items[0].stats_data[0].count # total_repo_count

          # Code Scanning alerts
          assert_equal 0, result.items[1].stats_data[0].items[0].count # affected_repo_count
          assert_equal 0, result.items[1].stats_data[1].count # open_alerts_count
          assert_equal 0, result.items[1].stats_data[0].count # total_repo_count

          # Secret Scanning alerts
          assert_equal 0, result.items[2].stats_data[0].items[0].count # affected_repo_count
          assert_equal 0, result.items[2].stats_data[1].count # open_alerts_count
          assert_equal 0, result.items[2].stats_data[0].count # total_repo_count
        end

        test "returns full structure for empty org" do
          result = new_query(scope: @org2).perform

          assert_stats_structure result

          result.items.each do |r|
            assert_equal 0, r.stats_data[0].items[0].count # affected_repo_count
            assert_equal 0, r.stats_data[1].count # open_alerts_count
            assert_equal 0, r.stats_data[0].count # total_repo_count
            r.stats_data.flat_map(&:items).each do |data_item|
              assert_equal 0, data_item.count
            end
          end
        end

        test "returns results limited by provided repository ids" do
          # no filter
          StatsQuery.for_organization(user: @org1_owner, user_session: @user_session, organization: @org1, parser: new_parser, repo_ids_by_feature: nil).perform.tap do |result|
            assert_stats_structure result

            # Dependabot alerts
            assert_equal 2, result.items[0].stats_data[0].items[0].count # affected_repo_count
            assert_equal 8, result.items[0].stats_data[1].count # open_alerts_count
            assert_equal 5, result.items[0].stats_data[0].count # total_repo_count
            assert_equal %w[critical high moderate low], result.items[0].stats_data[1].items.map(&:name)
            assert_equal 4, result.items[0].stats_data[1].items[0].count
            assert_equal 2, result.items[0].stats_data[1].items[1].count
            assert_equal 1, result.items[0].stats_data[1].items[2].count
            assert_equal 1, result.items[0].stats_data[1].items[3].count

            # Code Scanning alerts
            assert_equal 2, result.items[1].stats_data[0].items[0].count # affected_repo_count
            assert_equal 29, result.items[1].stats_data[1].count # open_alerts_count
            assert_equal 5, result.items[1].stats_data[0].count # total_repo_count
            assert_equal %w[critical high medium low informational], result.items[1].stats_data[1].items.map(&:name)
            assert_equal 1, result.items[1].stats_data[1].items[0].count
            assert_equal 2, result.items[1].stats_data[1].items[1].count
            assert_equal 4, result.items[1].stats_data[1].items[2].count
            assert_equal 4, result.items[1].stats_data[1].items[3].count
            assert_equal 18, result.items[1].stats_data[1].items[4].count

            # Secret Scanning alerts
            assert_equal 1, result.items[2].stats_data[0].items[0].count # affected_repo_count
            assert_equal 3, result.items[2].stats_data[1].count # open_alerts_count
            assert_equal 5, result.items[2].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[2].stats_data[1].items.map(&:name)
            assert_equal 3, result.items[2].stats_data[1].items[0].count
          end

          # partial filter
          repo_ids_by_feature = {
            dependabot_alerts: [@cs_repo, @dbot_repo, @ss_repo].map(&:id),
            code_scanning: [@cs_repo, @dbot_repo, @ss_repo].map(&:id),
            secret_scanning: [@cs_repo, @dbot_repo, @ss_repo].map(&:id),
          }
          StatsQuery.for_organization(user: @org1_owner, user_session: @user_session, organization: @org1, parser: new_parser, repo_ids_by_feature: repo_ids_by_feature).perform.tap do |result|
            assert_stats_structure result

            # Dependabot alerts
            assert_equal 1, result.items[0].stats_data[0].items[0].count # affected_repo_count
            assert_equal 7, result.items[0].stats_data[1].count # open_alerts_count
            assert_equal 3, result.items[0].stats_data[0].count # total_repo_count
            assert_equal %w[critical high moderate low], result.items[0].stats_data[1].items.map(&:name)
            assert_equal 3, result.items[0].stats_data[1].items[0].count
            assert_equal 2, result.items[0].stats_data[1].items[1].count
            assert_equal 1, result.items[0].stats_data[1].items[2].count
            assert_equal 1, result.items[0].stats_data[1].items[3].count

            # Code Scanning alerts
            assert_equal 1, result.items[1].stats_data[0].items[0].count # affected_repo_count
            assert_equal 28, result.items[1].stats_data[1].count # open_alerts_count
            assert_equal 3, result.items[1].stats_data[0].count # total_repo_count
            assert_equal %w[critical high medium low informational], result.items[1].stats_data[1].items.map(&:name)
            assert_equal 1, result.items[1].stats_data[1].items[0].count
            assert_equal 2, result.items[1].stats_data[1].items[1].count
            assert_equal 3, result.items[1].stats_data[1].items[2].count
            assert_equal 4, result.items[1].stats_data[1].items[3].count
            assert_equal 18, result.items[1].stats_data[1].items[4].count

            # Secret Scanning alerts
            assert_equal 1, result.items[2].stats_data[0].items[0].count # affected_repo_count
            assert_equal 3, result.items[2].stats_data[1].count # open_alerts_count
            assert_equal 3, result.items[2].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[2].stats_data[1].items.map(&:name)
            assert_equal 3, result.items[2].stats_data[1].items[0].count
          end

          # mixed access
          repo_ids_by_feature = {
            dependabot_alerts: [@cs_repo, @dbot_repo].map(&:id),
            code_scanning: [@cs_repo].map(&:id),
            secret_scanning: [],
          }
          StatsQuery.for_organization(user: @org1_owner, user_session: @user_session, organization: @org1, parser: new_parser, repo_ids_by_feature: repo_ids_by_feature).perform.tap do |result|
            assert_stats_structure result

            # Dependabot alerts
            assert_equal 1, result.items[0].stats_data[0].items[0].count # affected_repo_count
            assert_equal 7, result.items[0].stats_data[1].count # open_alerts_count
            assert_equal 2, result.items[0].stats_data[0].count # total_repo_count
            assert_equal %w[critical high moderate low], result.items[0].stats_data[1].items.map(&:name)
            assert_equal 3, result.items[0].stats_data[1].items[0].count
            assert_equal 2, result.items[0].stats_data[1].items[1].count
            assert_equal 1, result.items[0].stats_data[1].items[2].count
            assert_equal 1, result.items[0].stats_data[1].items[3].count

            # Code Scanning alerts
            assert_equal 1, result.items[1].stats_data[0].items[0].count # affected_repo_count
            assert_equal 28, result.items[1].stats_data[1].count # open_alerts_count
            assert_equal 1, result.items[1].stats_data[0].count # total_repo_count
            assert_equal %w[critical high medium low informational], result.items[1].stats_data[1].items.map(&:name)
            assert_equal 1, result.items[1].stats_data[1].items[0].count
            assert_equal 2, result.items[1].stats_data[1].items[1].count
            assert_equal 3, result.items[1].stats_data[1].items[2].count
            assert_equal 4, result.items[1].stats_data[1].items[3].count
            assert_equal 18, result.items[1].stats_data[1].items[4].count

            # Secret Scanning alerts
            assert_equal 0, result.items[2].stats_data[0].items[0].count # affected_repo_count
            assert_equal 0, result.items[2].stats_data[1].count # open_alerts_count
            assert_equal 0, result.items[2].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[2].stats_data[1].items.map(&:name)
            assert_equal 0, result.items[2].stats_data[1].items[0].count
          end

          # with feature filter
          repo_ids_by_feature = {
            dependabot_alerts: [@cs_repo, @dbot_repo, @ss_repo, @mixed_repo].map(&:id),
            code_scanning: [@cs_repo, @dbot_repo, @ss_repo, @mixed_repo].map(&:id),
            secret_scanning: [@cs_repo, @dbot_repo, @ss_repo, @mixed_repo].map(&:id),
          }
          StatsQuery.for_organization(user: @org1_owner, user_session: @user_session, organization: @org1, parser: new_parser("code-scanning-alerts:>0"), repo_ids_by_feature: repo_ids_by_feature).perform.tap do |result|
            assert_stats_structure result

            # Dependabot alerts
            assert_equal 1, result.items[0].stats_data[0].items[0].count # affected_repo_count
            assert_equal 1, result.items[0].stats_data[1].count # open_alerts_count
            assert_equal 2, result.items[0].stats_data[0].count # total_repo_count
            assert_equal %w[critical], result.items[0].stats_data[1].items.map(&:name)
            assert_equal 1, result.items[0].stats_data[1].items[0].count

            # Code Scanning alerts
            assert_equal 2, result.items[1].stats_data[0].items[0].count # affected_repo_count
            assert_equal 29, result.items[1].stats_data[1].count # open_alerts_count
            assert_equal 2, result.items[1].stats_data[0].count # total_repo_count
            assert_equal %w[critical high medium low informational], result.items[1].stats_data[1].items.map(&:name)
            assert_equal 1, result.items[1].stats_data[1].items[0].count
            assert_equal 2, result.items[1].stats_data[1].items[1].count
            assert_equal 4, result.items[1].stats_data[1].items[2].count
            assert_equal 4, result.items[1].stats_data[1].items[3].count
            assert_equal 18, result.items[1].stats_data[1].items[4].count

            # Secret Scanning alerts
            assert_equal 0, result.items[2].stats_data[0].items[0].count # affected_repo_count
            assert_equal 0, result.items[2].stats_data[1].count # open_alerts_count
            assert_equal 2, result.items[2].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[2].stats_data[1].items.map(&:name)
            assert_equal 0, result.items[2].stats_data[1].items[0].count
          end

          # all filter
          StatsQuery.for_organization(user: @org1_owner, user_session: @user_session, organization: @org1, parser: new_parser, repo_ids_by_feature: {}).perform.tap do |result|
            assert_stats_structure result

            # everything filtered out; no results
            result.items.each do |r|
              assert_equal 0, r.stats_data[0].items[0].count # affected_repo_count
              assert_equal 0, r.stats_data[1].count # open_alerts_count
              assert_equal 0, r.stats_data[0].count # total_repo_count
            end
          end
        end

        context "for businesses with enterprise managed users on Dotcom", skip_enterprise: true do
          test "includes EMU-owned repos" do
            # query as business owner
            result = new_query(user: @mt_owner, scope: @mt_biz, organizations: [@mt_org]).perform
            assert_stats_structure result

            # Dependabot alerts -- not yet visible on security center for EMU-owned repos
            assert_equal 0, result.items[0].stats_data[0].items[0].count # affected_repo_count
            assert_equal 0, result.items[0].stats_data[1].count # open_alerts_count
            assert_equal 6, result.items[0].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[0].stats_data[1].items.map(&:name)
            assert_equal 0, result.items[0].stats_data[1].items[0].count

            # Code Scanning alerts -- not yet supported for EMU-owned repos
            assert_equal 0, result.items[1].stats_data[0].items[0].count # affected_repo_count
            assert_equal 0, result.items[1].stats_data[1].count # open_alerts_count
            assert_equal 6, result.items[1].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[1].stats_data[1].items.map(&:name)
            assert_equal 0, result.items[1].stats_data[1].items[0].count

            # Secret Scanning alerts
            assert_equal 4, result.items[2].stats_data[0].items[0].count # affected_repo_count
            assert_equal 10, result.items[2].stats_data[1].count # open_alerts_count
            assert_equal 6, result.items[2].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[2].stats_data[1].items.map(&:name)
            assert_equal 10, result.items[2].stats_data[1].items[0].count
          end

          test "includes EMU-owned repos if user is an enterprise security manager" do
            # query as enterprise security manager
            result = new_query(user: @enterprise_security_manager, scope: @mt_biz, organizations: [@mt_org]).perform
            assert_stats_structure result

            # Dependabot alerts -- not yet visible on security center for EMU-owned repos
            assert_equal 0, result.items[0].stats_data[0].items[0].count # affected_repo_count
            assert_equal 0, result.items[0].stats_data[1].count # open_alerts_count
            assert_equal 6, result.items[0].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[0].stats_data[1].items.map(&:name)
            assert_equal 0, result.items[0].stats_data[1].items[0].count

            # Code Scanning alerts -- not yet supported for EMU-owned repos
            assert_equal 0, result.items[1].stats_data[0].items[0].count # affected_repo_count
            assert_equal 0, result.items[1].stats_data[1].count # open_alerts_count
            assert_equal 6, result.items[1].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[1].stats_data[1].items.map(&:name)
            assert_equal 0, result.items[1].stats_data[1].items[0].count

            # Secret Scanning alerts
            assert_equal 4, result.items[2].stats_data[0].items[0].count # affected_repo_count
            assert_equal 10, result.items[2].stats_data[1].count # open_alerts_count
            assert_equal 6, result.items[2].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[2].stats_data[1].items.map(&:name)
            assert_equal 10, result.items[2].stats_data[1].items[0].count
          end

          test "excludes EMU-owned repos if the user is not an owner of the business" do
            result = new_query(user: @mt_user, scope: @mt_biz, organizations: [@mt_org]).perform
            assert_stats_structure result

            ## Only results for @mt_org

            # Dependabot alerts -- not yet visible on security center for EMU-owned repos
            assert_equal 0, result.items[0].stats_data[0].items[0].count # affected_repo_count
            assert_equal 0, result.items[0].stats_data[1].count # open_alerts_count
            assert_equal 2, result.items[0].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[0].stats_data[1].items.map(&:name)
            assert_equal 0, result.items[0].stats_data[1].items[0].count

            # Code Scanning alerts -- not yet supported for EMU-owned repos
            assert_equal 0, result.items[1].stats_data[0].items[0].count # affected_repo_count
            assert_equal 0, result.items[1].stats_data[1].count # open_alerts_count
            assert_equal 2, result.items[1].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[1].stats_data[1].items.map(&:name)
            assert_equal 0, result.items[1].stats_data[1].items[0].count

            # Secret Scanning alerts
            assert_equal 1, result.items[2].stats_data[0].items[0].count # affected_repo_count
            assert_equal 4, result.items[2].stats_data[1].count # open_alerts_count
            assert_equal 2, result.items[2].stats_data[0].count # total_repo_count
            assert_equal 4, result.items[2].stats_data[1].items[0].count
          end

          test "excludes EMU-owned repos if GHAS is not purchased" do
            Business.any_instance.stubs(:advanced_security_purchased?).returns(false)

            # query as business owner
            result = new_query(user: @mt_owner, scope: @mt_biz, organizations: [@mt_org]).perform
            assert_stats_structure result

            # Dependabot alerts -- not yet visible on security center for EMU-owned repos
            assert_equal 0, result.items[0].stats_data[0].items[0].count # affected_repo_count
            assert_equal 0, result.items[0].stats_data[1].count # open_alerts_count
            assert_equal 2, result.items[0].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[0].stats_data[1].items.map(&:name)
            assert_equal 0, result.items[0].stats_data[1].items[0].count

            # Code Scanning alerts -- not yet supported for EMU-owned repos
            assert_equal 0, result.items[1].stats_data[0].items[0].count # affected_repo_count
            assert_equal 0, result.items[1].stats_data[1].count # open_alerts_count
            assert_equal 2, result.items[1].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[1].stats_data[1].items.map(&:name)
            assert_equal 0, result.items[1].stats_data[1].items[0].count

            # Secret Scanning alerts
            assert_equal 1, result.items[2].stats_data[0].items[0].count # affected_repo_count
            assert_equal 4, result.items[2].stats_data[1].count # open_alerts_count
            assert_equal 2, result.items[2].stats_data[0].count # total_repo_count
            assert_equal %w[alerts], result.items[2].stats_data[1].items.map(&:name)
            assert_equal 4, result.items[2].stats_data[1].items[0].count
          end

          context "filters" do
            [
              [
                "by specific org owner",
                "owner:test-org-emu", # maps to @mt_org
                { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 2, open_alerts_by_severity: {} },
                { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 2, open_alerts_by_severity: {} },
                { affected_repo_count: 1, open_alerts_count: 4, total_repo_count: 2 }
              ],
              [
                "org owner type",
                "owner-type:organization",
                { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 2, open_alerts_by_severity: {} },
                { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 2, open_alerts_by_severity: {} },
                { affected_repo_count: 1, open_alerts_count: 4, total_repo_count: 2 }
              ],
              [
                "user owner type",
                "owner-type:user",
                { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 4, open_alerts_by_severity: {} },
                { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 4, open_alerts_by_severity: {} },
                { affected_repo_count: 3, open_alerts_count: 6, total_repo_count: 4 }
              ],
              [
                "by specific user owner",
                "owner:mt-user_mtbiz",
                { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 4, open_alerts_by_severity: {} },
                { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 4, open_alerts_by_severity: {} },
                { affected_repo_count: 3, open_alerts_count: 6, total_repo_count: 4 }
              ],
            ].each do |test_name, query_string, expected_dbot_stats, expected_cs_stats, expected_ss_stats|
              test "by #{test_name}" do
                result = new_query(user: @mt_owner, scope: @mt_biz, organizations: [@mt_org], query_string: query_string).perform
                assert_stats_structure result

                # Dependabot alerts
                result.items[0].tap do |dbot_stats|
                  assert_equal expected_dbot_stats[:affected_repo_count], dbot_stats.stats_data[0].items[0].count # affected_repo_count
                  assert_equal expected_dbot_stats[:open_alerts_count], dbot_stats.stats_data[1].count # open_alerts_count
                  assert_equal expected_dbot_stats[:total_repo_count], dbot_stats.stats_data[0].count # total_repo_count
                  if expected_dbot_stats[:open_alerts_by_severity].present?
                    assert_equal expected_dbot_stats[:open_alerts_by_severity].keys, dbot_stats.stats_data[1].items.map(&:name)
                    expected_dbot_stats[:open_alerts_by_severity].each do |severity, count|
                      assert_equal count, dbot_stats.open_alerts_by_severity[severity]
                    end
                  else
                    assert_equal %w[alerts], dbot_stats.stats_data[1].items.map(&:name)
                    assert_equal expected_dbot_stats[:open_alerts_count], dbot_stats.stats_data[1].items[0].count
                  end
                end

                # Code Scanning alerts
                result.items[1].tap do |cs_stats|
                  assert_equal expected_cs_stats[:affected_repo_count], cs_stats.stats_data[0].items[0].count # affected_repo_count
                  assert_equal expected_cs_stats[:open_alerts_count], cs_stats.stats_data[1].count # open_alerts_count
                  assert_equal expected_cs_stats[:total_repo_count], cs_stats.stats_data[0].count # total_repo_count
                  if expected_cs_stats[:open_alerts_by_severity].present?
                    assert_equal expected_cs_stats[:open_alerts_by_severity].keys, cs_stats.stats_data[1].items.map(&:name)
                    expected_cs_stats[:open_alerts_by_severity].each do |severity, count|
                      assert_equal count, cs_stats.open_alerts_by_severity[severity]
                    end
                  else
                    assert_equal %w[alerts], cs_stats.stats_data[1].items.map(&:name)
                    assert_equal expected_cs_stats[:open_alerts_count], cs_stats.stats_data[1].items[0].count
                  end
                end

                # Secret Scanning alerts
                result.items[2].tap do |ss_stats|
                  assert_equal expected_ss_stats[:affected_repo_count], ss_stats.stats_data[0].items[0].count # affected_repo_count
                  assert_equal expected_ss_stats[:open_alerts_count], ss_stats.stats_data[1].count # open_alerts_count
                  assert_equal expected_ss_stats[:total_repo_count], ss_stats.stats_data[0].count # total_repo_count
                  assert_equal %w[alerts], ss_stats.stats_data[1].items.map(&:name)
                  assert_equal expected_ss_stats[:open_alerts_count], ss_stats.stats_data[1].items[0].count
                end
              end
            end
          end
        end

        context "for businesses without enterprise managed users on Dotcom", skip_enterprise: true do
          test "does not include user-owned repos" do
            result = new_query(scope: @business, organizations: [@org1]).perform

            assert_stats_structure result

            # Dependabot alerts
            assert_equal 2, result.items[0].stats_data[0].items[0].count # affected_repo_count
            assert_equal 8, result.items[0].stats_data[1].count # open_alerts_count
            assert_equal 5, result.items[0].stats_data[0].count # total_repo_count
            assert_equal %w[critical high moderate low], result.items[0].stats_data[1].items.map(&:name)
            assert_equal 4, result.items[0].stats_data[1].items[0].count
            assert_equal 2, result.items[0].stats_data[1].items[1].count
            assert_equal 1, result.items[0].stats_data[1].items[2].count
            assert_equal 1, result.items[0].stats_data[1].items[3].count

            # Code Scanning alerts
            assert_equal 2, result.items[1].stats_data[0].items[0].count # affected_repo_count
            assert_equal 29, result.items[1].stats_data[1].count # open_alerts_count
            assert_equal 5, result.items[1].stats_data[0].count # total_repo_count
            assert_equal %w[critical high medium low informational], result.items[1].stats_data[1].items.map(&:name)
            assert_equal 1, result.items[1].stats_data[1].items[0].count
            assert_equal 2, result.items[1].stats_data[1].items[1].count
            assert_equal 4, result.items[1].stats_data[1].items[2].count
            assert_equal 4, result.items[1].stats_data[1].items[3].count
            assert_equal 18, result.items[1].stats_data[1].items[4].count

            # Secret Scanning alerts
            assert_equal 1, result.items[2].stats_data[0].items[0].count # affected_repo_count
            assert_equal 3, result.items[2].stats_data[1].count # open_alerts_count
            assert_equal 5, result.items[2].stats_data[0].count # total_repo_count
            assert_equal 3, result.items[2].stats_data[1].items[0].count
          end
        end

        context "for businesses with user-owned repositories on GHES", enterprise_only: true do
          test "includes user-owned repos if feature flag is enabled" do
            GitHub.stubs(:security_center_for_emus_enabled?).returns(true)

            result = new_query(scope: @business, organizations: [@org1]).perform

            assert_stats_structure result

            # Dependabot alerts -- not yet visible on security center for EMU-owned repos
            assert_equal 2, result.items[0].stats_data[0].items[0].count # affected_repo_count
            assert_equal 8, result.items[0].stats_data[1].count # open_alerts_count
            assert_equal 7, result.items[0].stats_data[0].count # total_repo_count
            assert_equal %w[critical high moderate low], result.items[0].stats_data[1].items.map(&:name)
            assert_equal 4, result.items[0].stats_data[1].items[0].count
            assert_equal 2, result.items[0].stats_data[1].items[1].count
            assert_equal 1, result.items[0].stats_data[1].items[2].count
            assert_equal 1, result.items[0].stats_data[1].items[3].count

            # Code Scanning alerts -- not yet supported for EMU-owned repos
            assert_equal 2, result.items[1].stats_data[0].items[0].count # affected_repo_count
            assert_equal 29, result.items[1].stats_data[1].count # open_alerts_count
            assert_equal 7, result.items[1].stats_data[0].count # total_repo_count
            assert_equal %w[critical high medium low informational], result.items[1].stats_data[1].items.map(&:name)
            assert_equal 1, result.items[1].stats_data[1].items[0].count
            assert_equal 2, result.items[1].stats_data[1].items[1].count
            assert_equal 4, result.items[1].stats_data[1].items[2].count
            assert_equal 4, result.items[1].stats_data[1].items[3].count
            assert_equal 18, result.items[1].stats_data[1].items[4].count

            # Secret Scanning alerts
            assert_equal 2, result.items[2].stats_data[0].items[0].count # affected_repo_count
            assert_equal 6, result.items[2].stats_data[1].count # open_alerts_count
            assert_equal 7, result.items[2].stats_data[0].count # total_repo_count
            assert_equal 6, result.items[2].stats_data[1].items[0].count
          end

          test "excludes user-owned repos if GHAS is not purchased" do
            GitHub.stubs(:security_center_for_emus_enabled?).returns(true)
            Business.any_instance.stubs(:advanced_security_purchased?).returns(false)

            result = new_query(scope: @business, organizations: [@org1]).perform

            assert_equal 1, result.items.length # limited security center, only dependabot alerts visible

            # Dependabot alerts -- not yet visible on security center for EMU-owned repos
            assert_equal 2, result.items[0].stats_data[0].items[0].count # affected_repo_count
            assert_equal 8, result.items[0].stats_data[1].count # open_alerts_count
            assert_equal 5, result.items[0].stats_data[0].count # total_repo_count
            assert_equal %w[critical high moderate low], result.items[0].stats_data[1].items.map(&:name)
            assert_equal 4, result.items[0].stats_data[1].items[0].count
            assert_equal 2, result.items[0].stats_data[1].items[1].count
            assert_equal 1, result.items[0].stats_data[1].items[2].count
            assert_equal 1, result.items[0].stats_data[1].items[3].count
          end

          test "excludes user-owned repos if feature flag is not enabled" do
            GitHub.stubs(:security_center_for_emus_enabled?).returns(false)

            result = new_query(scope: @business, organizations: [@org1]).perform

            assert_stats_structure result

            # Dependabot alerts -- not yet visible on security center for EMU-owned repos
            assert_equal 2, result.items[0].stats_data[0].items[0].count # affected_repo_count
            assert_equal 8, result.items[0].stats_data[1].count # open_alerts_count
            assert_equal 5, result.items[0].stats_data[0].count # total_repo_count
            assert_equal %w[critical high moderate low], result.items[0].stats_data[1].items.map(&:name)
            assert_equal 4, result.items[0].stats_data[1].items[0].count
            assert_equal 2, result.items[0].stats_data[1].items[1].count
            assert_equal 1, result.items[0].stats_data[1].items[2].count
            assert_equal 1, result.items[0].stats_data[1].items[3].count

            # Code Scanning alerts -- not yet supported for EMU-owned repos
            assert_equal 2, result.items[1].stats_data[0].items[0].count # affected_repo_count
            assert_equal 29, result.items[1].stats_data[1].count # open_alerts_count
            assert_equal 5, result.items[1].stats_data[0].count # total_repo_count
            assert_equal %w[critical high medium low informational], result.items[1].stats_data[1].items.map(&:name)
            assert_equal 1, result.items[1].stats_data[1].items[0].count
            assert_equal 2, result.items[1].stats_data[1].items[1].count
            assert_equal 4, result.items[1].stats_data[1].items[2].count
            assert_equal 4, result.items[1].stats_data[1].items[3].count
            assert_equal 18, result.items[1].stats_data[1].items[4].count

            # Secret Scanning alerts
            assert_equal 1, result.items[2].stats_data[0].items[0].count # affected_repo_count
            assert_equal 3, result.items[2].stats_data[1].count # open_alerts_count
            assert_equal 5, result.items[2].stats_data[0].count # total_repo_count
            assert_equal 3, result.items[2].stats_data[1].items[0].count
          end
        end

        context "executes expected number of queries" do
          test "when user has access to all repositories" do
            assert_query_count(GitHub.enterprise? ? 1 : 3, ignore_feature_flags: true) do
              new_query.perform
            end
          end

          test "when user has access to subset of repositories" do
            repo_ids_by_feature = {
              dependabot_alerts: [@dbot_repo].map(&:id),
              code_scanning: [@cs_repo].map(&:id),
              secret_scanning: [@ss_repo].map(&:id),
            }
            # soa_feature_status per feature (3)
            assert_query_count(GitHub.enterprise? ? 3 : 5) do
              query = StatsQuery.for_organization(user: @org1_owner, user_session: @user_session, organization: @org1, parser: new_parser, repo_ids_by_feature: repo_ids_by_feature)
              query.perform
            end
          end
        end

        test "only returns data for security features enabled for the instance" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          assert_query_count(GitHub.enterprise? ? 1 : 3) do
            assert_equal ["Dependabot", "Code scanning", "Secret scanning"], new_query.perform.items.map(&:title)
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: false,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          assert_query_count(1) do
            assert_equal ["Dependabot", "Secret scanning"], new_query.perform.items.map(&:title)
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: false,
            dependabot_alerts_enabled_for_instance?: true,
          )

          assert_query_count(1) do
            assert_equal ["Dependabot", "Code scanning"], new_query.perform.items.map(&:title)
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: false,
          )

          assert_query_count(1) do
            assert_equal ["Code scanning", "Secret scanning"], new_query.perform.items.map(&:title)
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: false,
            secret_scanning_enabled_for_instance?: false,
            dependabot_alerts_enabled_for_instance?: false,
          )

          assert_query_count(0) do
            assert_empty new_query.perform.items
          end
        end

        context "filters" do
          [
            [
              "unqualified term",
              "mixed",
              { affected_repo_count: 1, open_alerts_count: 1, total_repo_count: 1, open_alerts_by_severity: { critical: 1 } },
              { affected_repo_count: 1, open_alerts_count: 1, total_repo_count: 1, open_alerts_by_severity: { medium: 1 } },
              { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 1 }
            ],
            [
              "repository name",
              "repo:test-org-1-mixed-repo",
              { affected_repo_count: 1, open_alerts_count: 1, total_repo_count: 1, open_alerts_by_severity: { critical: 1 } },
              { affected_repo_count: 1, open_alerts_count: 1, total_repo_count: 1, open_alerts_by_severity: { medium: 1 } },
              { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 1 }
            ],
            [
              "visibility",
              "is:private",
              { affected_repo_count: 2, open_alerts_count: 8, total_repo_count: 5, open_alerts_by_severity: { critical: 4, high: 2, moderate: 1, low: 1 } },
              { affected_repo_count: 2, open_alerts_count: 29, total_repo_count: 5, open_alerts_by_severity: { critical: 1, high: 2, medium: 4, low: 4, informational: 18 } },
              { affected_repo_count: 1, open_alerts_count: 3, total_repo_count: 5 }
            ],
            [
              "archived",
              "archived:true",
              { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 0, open_alerts_by_severity: {} },
              { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 0, open_alerts_by_severity: {} },
              { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 0 }
            ],
            [
              "team",
              "team:banana",
              { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 1, open_alerts_by_severity: {} },
              { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 1, open_alerts_by_severity: {} },
              { affected_repo_count: 1, open_alerts_count: 3, total_repo_count: 1 }
            ],
            [
              "topic",
              "topic:apples",
              { affected_repo_count: 1, open_alerts_count: 7, total_repo_count: 1, open_alerts_by_severity: { critical: 3, high: 2, moderate: 1, low: 1 } },
              { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 1, open_alerts_by_severity: {} },
              { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 1 }
            ],
            [
              "dependabot-alerts",
              "dependabot-alerts:>0",
              { affected_repo_count: 2, open_alerts_count: 8, total_repo_count: 2, open_alerts_by_severity: { critical: 4, high: 2, moderate: 1, low: 1 } },
              { affected_repo_count: 1, open_alerts_count: 1, total_repo_count: 2, open_alerts_by_severity: { medium: 1 } },
              { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 2 }
            ],
            [
              "code-scanning-alerts",
              "code-scanning-alerts:>0",
              { affected_repo_count: 1, open_alerts_count: 1, total_repo_count: 2, open_alerts_by_severity: { critical: 1 } },
              { affected_repo_count: 2, open_alerts_count: 29, total_repo_count: 2, open_alerts_by_severity: { critical: 1, high: 2, medium: 4, low: 4, informational: 18 } },
              { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 2 }
            ],
            [
              "secret-scanning",
              "secret-scanning-alerts:>0",
              { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 1, open_alerts_by_severity: {} },
              { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 1, open_alerts_by_severity: {} },
              { affected_repo_count: 1, open_alerts_count: 3, total_repo_count: 1 }
            ],
            [
              "has-severity",
              "has-severity:medium",
              { affected_repo_count: 1, open_alerts_count: 1, total_repo_count: 2, open_alerts_by_severity: { critical: 1 } },
              { affected_repo_count: 2, open_alerts_count: 29, total_repo_count: 2, open_alerts_by_severity: { critical: 1, high: 2, medium: 4, low: 4, informational: 18 } },
              { affected_repo_count: 0, open_alerts_count: 0, total_repo_count: 2 }
            ]
          ].each do |test_name, query_string, expected_dbot_stats, expected_cs_stats, expected_ss_stats|
            test "by #{test_name}" do
              result = new_query(query_string: query_string).perform

              assert_stats_structure result

              # Dependabot alerts
              result.items[0].tap do |dbot_stats|
                assert_equal expected_dbot_stats[:affected_repo_count], dbot_stats.stats_data[0].items[0].count # affected_repo_count
                assert_equal expected_dbot_stats[:open_alerts_count], dbot_stats.stats_data[1].count # open_alerts_count
                assert_equal expected_dbot_stats[:total_repo_count], dbot_stats.stats_data[0].count # total_repo_count
                if expected_dbot_stats[:open_alerts_by_severity].present?
                  assert_equal expected_dbot_stats[:open_alerts_by_severity].keys, dbot_stats.stats_data[1].items.map(&:name).map(&:to_sym)
                  expected_dbot_stats[:open_alerts_by_severity].each do |severity, count|
                    assert_equal count, dbot_stats.stats_data[1].items.find { |di| di.name.to_sym == severity }.count
                  end
                else
                  assert_equal %w[alerts], dbot_stats.stats_data[1].items.map(&:name)
                  assert_equal expected_dbot_stats[:open_alerts_count], dbot_stats.stats_data[1].items[0].count
                end
              end

              # Code Scanning alerts
              result.items[1].tap do |cs_stats|
                assert_equal expected_cs_stats[:affected_repo_count], cs_stats.stats_data[0].items[0].count # affected_repo_count
                assert_equal expected_cs_stats[:open_alerts_count], cs_stats.stats_data[1].count # open_alerts_count
                assert_equal expected_cs_stats[:total_repo_count], cs_stats.stats_data[0].count # total_repo_count
                if expected_cs_stats[:open_alerts_by_severity].present?
                  assert_equal expected_cs_stats[:open_alerts_by_severity].keys, cs_stats.stats_data[1].items.map(&:name).map(&:to_sym)
                  expected_cs_stats[:open_alerts_by_severity].each do |severity, count|
                    assert_equal count, cs_stats.stats_data[1].items.find { |di| di.name.to_sym == severity }.count
                  end
                else
                  assert_equal %w[alerts], cs_stats.stats_data[1].items.map(&:name)
                  assert_equal expected_cs_stats[:open_alerts_count], cs_stats.stats_data[1].items[0].count
                end
              end

              # Secret Scanning alerts
              result.items[2].tap do |ss_stats|
                assert_equal expected_ss_stats[:affected_repo_count], ss_stats.stats_data[0].items[0].count # affected_repo_count
                assert_equal expected_ss_stats[:open_alerts_count], ss_stats.stats_data[1].count # open_alerts_count
                assert_equal expected_ss_stats[:total_repo_count], ss_stats.stats_data[0].count # total_repo_count
                assert_equal %w[alerts], ss_stats.stats_data[1].items.map(&:name)
                assert_equal expected_ss_stats[:open_alerts_count], ss_stats.stats_data[1].items[0].count
              end
            end
          end
        end

        context "urls" do
          test "returns expected query params for each stat item" do
            result = new_query.perform
            assert_equal 3, result.items.length

            result.items[0].tap do |r|
              assert_equal "Dependabot", r.title
              assert_equal 2, r.stats_data.length

              r.stats_data[0].tap do |stat|
                assert_equal "Repositories", stat.title
                assert_url_params stat.href, query: "dependabot-alerts:>0"
                assert_equal 2, stat.items.length

                stat.items[0].tap do |item|
                  assert_equal "affected", item.name
                  assert_url_params item.href, query: "dependabot-alerts:>0"
                end

                stat.items[1].tap do |item|
                  assert_equal "unaffected", item.name
                  assert_url_params item.href, query: 'dependabot-alerts:"not-enabled,0"'
                end
              end

              r.stats_data[1].tap do |stat|
                assert_equal "Open alerts", stat.title
                assert_url_params stat.href, query: "dependabot-alerts:>0"
                assert_operator stat.items.length, :>=, 1

                if stat.count > 0
                  # If there are alerts, we have one or more severity segments
                  stat.items.each do |item|
                    assert_url_params item.href, query: "dependabot-alerts:>0 has-severity:#{item.name}"
                  end
                else
                  # If no alerts, there's still one segment placeholder
                  stat.items[0].tap do |item|
                    assert_url_params item.href, query: "dependabot-alerts:>0"
                  end
                end
              end
            end

            result.items[1].tap do |r|
              assert_equal "Code scanning", r.title
              assert_equal 2, r.stats_data.length

              r.stats_data[0].tap do |stat|
                assert_equal "Repositories", stat.title
                assert_url_params stat.href, query: "code-scanning-alerts:>0"
                assert_equal 2, stat.items.length

                stat.items[0].tap do |item|
                  assert_equal "affected", item.name
                  assert_url_params item.href, query: "code-scanning-alerts:>0"
                end

                stat.items[1].tap do |item|
                  assert_equal "unaffected", item.name
                  assert_url_params item.href, query: 'code-scanning-alerts:"not-enabled,0"'
                end
              end

              r.stats_data[1].tap do |stat|
                assert_equal "Open alerts", stat.title
                assert_url_params stat.href, query: "code-scanning-alerts:>0"
                assert_operator stat.items.length, :>=, 1

                if stat.count > 0
                  # If there are alerts, we have one or more severity segments
                  stat.items.each do |item|
                    assert_url_params item.href, query: "code-scanning-alerts:>0 has-severity:#{item.name}"
                  end
                else
                  # If no alerts, there's still one segment placeholder
                  stat.items[0].tap do |item|
                    assert_url_params item.href, query: "code-scanning-alerts:>0"
                  end
                end
              end
            end

            result.items[2].tap do |r|
              assert_equal "Secret scanning", r.title
              assert_equal 2, r.stats_data.length

              r.stats_data[0].tap do |stat|
                assert_equal "Repositories", stat.title
                assert_url_params stat.href, query: "secret-scanning-alerts:>0"
                assert_equal 2, stat.items.length

                stat.items[0].tap do |item|
                  assert_equal "affected", item.name
                  assert_url_params item.href, query: "secret-scanning-alerts:>0"
                end

                stat.items[1].tap do |item|
                  assert_equal "unaffected", item.name
                  assert_url_params item.href, query: 'secret-scanning-alerts:"not-enabled,0"'
                end
              end

              r.stats_data[1].tap do |stat|
                assert_equal "Open alerts", stat.title
                assert_url_params stat.href, query: "secret-scanning-alerts:>0"
                assert_equal 1, stat.items.length

                # Secret scanning has no severity, so always gets the fallback
                stat.items[0].tap do |item|
                  assert_url_params item.href, query: "secret-scanning-alerts:>0"
                end
              end
            end
          end

          context "#risk_path_url" do
            test "returns url with feature term" do
              sut = new_query
              result = sut.send(:risk_path_url, :dependabot_alerts, ">0")
              expected = "dependabot-alerts:>0"
              assert_equal "/orgs/#{@org1}/security/risk?query=#{CGI.escape(expected)}", result
            end

            test "handles duplicate feature term" do
              sut = new_query(query_string: "dependabot-alerts:not-enabled")
              result = sut.send(:risk_path_url, :dependabot_alerts, ">0")
              expected = "dependabot-alerts:>0"
              assert_equal "/orgs/#{@org1}/security/risk?query=#{CGI.escape(expected)}", result
            end

            test "handles business scope url" do
              sut = new_query(scope: @business, organizations: [@org1])
              result = sut.send(:risk_path_url, :dependabot_alerts, ">0")
              expected = "dependabot-alerts:>0"
              assert_equal "/enterprises/#{@business}/security/risk?query=#{CGI.escape(expected)}", result
            end
          end

          context "#feature_severity_filter_url" do
            test "returns url with feature and severity terms" do
              sut = new_query
              result = sut.send(:feature_severity_filter_url, :dependabot_alerts, :critical)
              expected = "dependabot-alerts:>0 has-severity:critical"
              assert_equal "/orgs/#{@org1}/security/risk?query=#{CGI.escape(expected)}", result
            end

            test "handles duplicate filter pair" do
              sut = new_query(query_string: "dependabot-alerts:>0 has-severity:critical")
              result = sut.send(:feature_severity_filter_url, :dependabot_alerts, :critical)
              expected = "dependabot-alerts:>0 has-severity:critical"
              assert_equal "/orgs/#{@org1}/security/risk?query=#{CGI.escape(expected)}", result
            end

            test "handles duplicate feature value" do
              sut = new_query(query_string: "dependabot-alerts:>0 has-severity:critical")
              result = sut.send(:feature_severity_filter_url, :dependabot_alerts, :high)
              expected = "dependabot-alerts:>0 has-severity:critical,high"
              assert_equal "/orgs/#{@org1}/security/risk?query=#{CGI.escape(expected)}", result
            end

            test "handles duplicate severity value" do
              sut = new_query(query_string: "dependabot-alerts:>0 has-severity:critical")
              result = sut.send(:feature_severity_filter_url, :code_scanning, :critical)
              expected = "dependabot-alerts:>0 has-severity:critical code-scanning-alerts:>0"
              assert_equal "/orgs/#{@org1}/security/risk?query=#{CGI.escape(expected)}", result
            end

            test "handles business scope url" do
              sut = new_query(scope: @business, organizations: [@org1])
              result = sut.send(:feature_severity_filter_url, :dependabot_alerts, :critical)
              expected = "dependabot-alerts:>0 has-severity:critical"
              assert_equal "/enterprises/#{@business}/security/risk?query=#{CGI.escape(expected)}", result
            end
          end
        end
      end

      private

      def new_query(user: @org1_owner, scope: @org1, query_string: "", organizations: nil)
        if scope.is_a?(Organization)
          StatsQuery.for_organization(user: user, user_session: @user_session, organization: scope, parser: new_parser(query_string))
        else
          StatsQuery.for_business(user: user, business: scope, parser: new_parser(query_string), organizations: {
            read_code_scanning: organizations,
            view_dependabot_alerts: organizations,
            viedw_secret_scanning_alerts: organizations,
          })
        end
      end

      def new_parser(query_string = "")
        ::Search::Queries::SecurityCenter::RiskQueryParser.new(query_string)
      end

      def create_repo(name, owner:, dbot_counts: {}, cs_counts: {}, ss_counts: {})
        create(:private_repository, name: name, owner: owner).tap do |repository|
          repository_metadata = create(:soa_repository, repository:)

          create(
            :soa_feature_status,
            repository_metadata:,
            advanced_security_status: "ENABLED",
            dependabot_alerts_status: dbot_counts.values.sum > 0 ? "ENABLED" : "NOT_ENABLED",
            dependabot_alerts_total_count: dbot_counts.values.sum,
            dependabot_alerts_critical_count: dbot_counts[:critical] || 0,
            dependabot_alerts_high_count: dbot_counts[:high] || 0,
            dependabot_alerts_medium_count: dbot_counts[:moderate] || 0,
            dependabot_alerts_low_count: dbot_counts[:low] || 0,
            code_scanning_alerts_status: cs_counts.values.sum > 0 ? "ENABLED" : "NOT_ENABLED",
            code_scanning_alerts_total_count: cs_counts.values.sum,
            code_scanning_alerts_critical_count: cs_counts[:critical] || 0,
            code_scanning_alerts_high_count: cs_counts[:high] || 0,
            code_scanning_alerts_medium_count: cs_counts[:medium] || 0,
            code_scanning_alerts_low_count: cs_counts[:low] || 0,
            code_scanning_alerts_info_count: \
              (cs_counts[:error] || 0) +
              (cs_counts[:warning] || 0) +
              (cs_counts[:note] || 0),
            secret_scanning_alerts_status: ss_counts.values.sum > 0 ? "ENABLED" : "NOT_ENABLED",
            secret_scanning_alerts_total_count: ss_counts.values.sum,
          )
        end
      end

      sig { params(result: StatsQuery::Result).void }
      def assert_stats_structure(result)
        assert_equal 3, result.items.length

        result.items[0].tap do |r|
          assert_equal "Dependabot", r.title
          assert_equal 2, r.stats_data.length

          r.stats_data[0].tap do |stat|
            assert_equal "Repositories", stat.title
            assert_operator stat.count, :>=, 0
            assert_equal 2, stat.items.length

            stat.items[0].tap do |item|
              assert_equal "affected", item.name
              assert_operator item.count, :>=, 0
            end

            stat.items[1].tap do |item|
              assert_equal "unaffected", item.name
              assert_operator item.count, :>=, 0
            end
          end

          r.stats_data[1].tap do |stat|
            assert_equal "Open alerts", stat.title
            assert_operator stat.count, :>=, 0
            assert_operator stat.items.length, :>=, 1

            if stat.count > 0
              # If there are alerts, we have one or more severity segments
              stat.items.each do |item|
                assert_includes %w[critical high moderate low], item.name
                assert_operator item.count, :>=, 1
              end
            else
              # If no alerts, there's still one segment placeholder
              stat.items[0].tap do |item|
                assert_equal "alerts", item.name
                assert_equal 0, item.count
              end
            end
          end
        end

        result.items[1].tap do |r|
          assert_equal "Code scanning", r.title
          assert_equal 2, r.stats_data.length

          r.stats_data[0].tap do |stat|
            assert_equal "Repositories", stat.title
            assert_operator stat.count, :>=, 0
            assert_equal 2, stat.items.length

            stat.items[0].tap do |item|
              assert_equal "affected", item.name
              assert_operator item.count, :>=, 0
            end

            stat.items[1].tap do |item|
              assert_equal "unaffected", item.name
              assert_operator item.count, :>=, 0
            end
          end

          r.stats_data[1].tap do |stat|
            assert_equal "Open alerts", stat.title
            assert_operator stat.count, :>=, 0
            assert_operator stat.items.length, :>=, 1

            if stat.count > 0
              # If there are alerts, we have one or more severity segments
              stat.items.each do |item|
                assert_includes %w[critical high medium low informational], item.name
                assert_operator item.count, :>=, 1
              end
            else
              # If no alerts, there's still one segment placeholder
              stat.items[0].tap do |item|
                assert_equal "alerts", item.name
                assert_equal 0, item.count
              end
            end
          end
        end

        result.items[2].tap do |r|
          assert_equal "Secret scanning", r.title
          assert_equal 2, r.stats_data.length

          r.stats_data[0].tap do |stat|
            assert_equal "Repositories", stat.title
            assert_operator stat.count, :>=, 0
            assert_equal 2, stat.items.length

            stat.items[0].tap do |item|
              assert_equal "affected", item.name
              assert_operator item.count, :>=, 0
            end

            stat.items[1].tap do |item|
              assert_equal "unaffected", item.name
              assert_operator item.count, :>=, 0
            end
          end

          r.stats_data[1].tap do |stat|
            assert_equal "Open alerts", stat.title
            assert_operator stat.count, :>=, 0
            assert_equal 1, stat.items.length

            # Secret scanning has no severity, so always gets the fallback
            stat.items[0].tap do |item|
              assert_equal "alerts", item.name
              assert_operator item.count, :>=, 0
            end
          end
        end
      end
    end
  end
end
