# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Risk
    class RiskStatsDataQueryTest < GitHub::TestCase
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
          result = new_query.run

          assert_stats_structure result

          # Dependabot alerts
          assert_equal 2, result[0].affected_repo_count
          assert_equal 8, result[0].open_alerts_count
          assert_equal 5, result[0].total_repo_count
          assert_equal [:critical, :high, :moderate, :low], result[0].open_alerts_by_severity.keys
          assert_equal 4, result[0].open_alerts_by_severity[:critical]
          assert_equal 2, result[0].open_alerts_by_severity[:high]
          assert_equal 1, result[0].open_alerts_by_severity[:moderate]
          assert_equal 1, result[0].open_alerts_by_severity[:low]

          # Code Scanning alerts
          assert_equal 2, result[1].affected_repo_count
          assert_equal 29, result[1].open_alerts_count
          assert_equal 5, result[1].total_repo_count
          assert_equal [:critical, :high, :medium, :low, :informational], result[1].open_alerts_by_severity.keys
          assert_equal 1, result[1].open_alerts_by_severity[:critical]
          assert_equal 2, result[1].open_alerts_by_severity[:high]
          assert_equal 4, result[1].open_alerts_by_severity[:medium]
          assert_equal 4, result[1].open_alerts_by_severity[:low]
          assert_equal 18, result[1].open_alerts_by_severity[:informational]

          # Secret Scanning alerts
          assert_equal 1, result[2].affected_repo_count
          assert_equal 3, result[2].open_alerts_count
          assert_equal 5, result[2].total_repo_count
          assert_empty result[2].open_alerts_by_severity
        end

        test "returns nothing when there is a mismatch in the business and organizations", skip_enterprise: true do
          GitHub.flipper[:security_center_include_biz_on_status_queries].enable

          other_emu = create(:emu)
          other_biz = other_emu.enterprise_managed_business

          # The business, passed in via scope, does not own anything inside organizations
          # so we should get 0 records
          result = new_query(scope: other_biz, organizations: [@mt_org]).run

          assert_stats_structure result

          # Dependabot alerts
          assert_equal 0, result[0].affected_repo_count
          assert_equal 0, result[0].open_alerts_count
          assert_equal 0, result[0].total_repo_count

          # Code Scanning alerts
          assert_equal 0, result[1].affected_repo_count
          assert_equal 00, result[1].open_alerts_count
          assert_equal 0, result[1].total_repo_count

          # Secret Scanning alerts
          assert_equal 0, result[2].affected_repo_count
          assert_equal 0, result[2].open_alerts_count
          assert_equal 0, result[2].total_repo_count
        end

        test "returns full structure for empty org" do
          result = new_query(scope: @org2).run

          assert_stats_structure result

          result.each do |r|
            assert_equal 0, r.affected_repo_count
            assert_equal 0, r.open_alerts_count
            assert_equal 0, r.total_repo_count
            assert_empty r.open_alerts_by_severity
          end
        end

        test "returns results limited by provided repository ids" do
          # no filter
          StatsDataQuery.for_organization(current_user: @org1_owner, user_session: @user_session, organization: @org1, parser: new_parser, repo_ids_by_feature: nil).run.tap do |result|
            assert_stats_structure result

            # Dependabot alerts
            assert_equal 2, result[0].affected_repo_count
            assert_equal 8, result[0].open_alerts_count
            assert_equal 5, result[0].total_repo_count
            assert_equal [:critical, :high, :moderate, :low], result[0].open_alerts_by_severity.keys
            assert_equal 4, result[0].open_alerts_by_severity[:critical]
            assert_equal 2, result[0].open_alerts_by_severity[:high]
            assert_equal 1, result[0].open_alerts_by_severity[:moderate]
            assert_equal 1, result[0].open_alerts_by_severity[:low]

            # Code Scanning alerts
            assert_equal 2, result[1].affected_repo_count
            assert_equal 29, result[1].open_alerts_count
            assert_equal 5, result[1].total_repo_count
            assert_equal [:critical, :high, :medium, :low, :informational], result[1].open_alerts_by_severity.keys
            assert_equal 1, result[1].open_alerts_by_severity[:critical]
            assert_equal 2, result[1].open_alerts_by_severity[:high]
            assert_equal 4, result[1].open_alerts_by_severity[:medium]
            assert_equal 4, result[1].open_alerts_by_severity[:low]
            assert_equal 18, result[1].open_alerts_by_severity[:informational]

            # Secret Scanning alerts
            assert_equal 1, result[2].affected_repo_count
            assert_equal 3, result[2].open_alerts_count
            assert_equal 5, result[2].total_repo_count
            assert_empty result[2].open_alerts_by_severity
          end

          # partial filter
          repo_ids_by_feature = {
            dependabot_alerts: [@cs_repo, @dbot_repo, @ss_repo].map(&:id),
            code_scanning: [@cs_repo, @dbot_repo, @ss_repo].map(&:id),
            secret_scanning: [@cs_repo, @dbot_repo, @ss_repo].map(&:id),
          }
          StatsDataQuery.for_organization(current_user: @org1_owner, user_session: @user_session, organization: @org1, parser: new_parser, repo_ids_by_feature: repo_ids_by_feature).run.tap do |result|
            assert_stats_structure result

            # Dependabot alerts
            assert_equal 1, result[0].affected_repo_count
            assert_equal 7, result[0].open_alerts_count
            assert_equal 3, result[0].total_repo_count
            assert_equal [:critical, :high, :moderate, :low], result[0].open_alerts_by_severity.keys
            assert_equal 3, result[0].open_alerts_by_severity[:critical]
            assert_equal 2, result[0].open_alerts_by_severity[:high]
            assert_equal 1, result[0].open_alerts_by_severity[:moderate]
            assert_equal 1, result[0].open_alerts_by_severity[:low]

            # Code Scanning alerts
            assert_equal 1, result[1].affected_repo_count
            assert_equal 28, result[1].open_alerts_count
            assert_equal 3, result[1].total_repo_count
            assert_equal [:critical, :high, :medium, :low, :informational], result[1].open_alerts_by_severity.keys
            assert_equal 1, result[1].open_alerts_by_severity[:critical]
            assert_equal 2, result[1].open_alerts_by_severity[:high]
            assert_equal 3, result[1].open_alerts_by_severity[:medium]
            assert_equal 4, result[1].open_alerts_by_severity[:low]
            assert_equal 18, result[1].open_alerts_by_severity[:informational]

            # Secret Scanning alerts
            assert_equal 1, result[2].affected_repo_count
            assert_equal 3, result[2].open_alerts_count
            assert_equal 3, result[2].total_repo_count
            assert_empty result[2].open_alerts_by_severity
          end

          # mixed access
          repo_ids_by_feature = {
            dependabot_alerts: [@cs_repo, @dbot_repo].map(&:id),
            code_scanning: [@cs_repo].map(&:id),
            secret_scanning: [],
          }
          StatsDataQuery.for_organization(current_user: @org1_owner, user_session: @user_session, organization: @org1, parser: new_parser, repo_ids_by_feature: repo_ids_by_feature).run.tap do |result|
            assert_stats_structure result

            # Dependabot alerts
            assert_equal 1, result[0].affected_repo_count
            assert_equal 7, result[0].open_alerts_count
            assert_equal 2, result[0].total_repo_count
            assert_equal [:critical, :high, :moderate, :low], result[0].open_alerts_by_severity.keys
            assert_equal 3, result[0].open_alerts_by_severity[:critical]
            assert_equal 2, result[0].open_alerts_by_severity[:high]
            assert_equal 1, result[0].open_alerts_by_severity[:moderate]
            assert_equal 1, result[0].open_alerts_by_severity[:low]

            # Code Scanning alerts
            assert_equal 1, result[1].affected_repo_count
            assert_equal 28, result[1].open_alerts_count
            assert_equal 1, result[1].total_repo_count
            assert_equal [:critical, :high, :medium, :low, :informational], result[1].open_alerts_by_severity.keys
            assert_equal 1, result[1].open_alerts_by_severity[:critical]
            assert_equal 2, result[1].open_alerts_by_severity[:high]
            assert_equal 3, result[1].open_alerts_by_severity[:medium]
            assert_equal 4, result[1].open_alerts_by_severity[:low]
            assert_equal 18, result[1].open_alerts_by_severity[:informational]

            # Secret Scanning alerts
            assert_equal 0, result[2].affected_repo_count
            assert_equal 0, result[2].open_alerts_count
            assert_equal 0, result[2].total_repo_count
            assert_empty result[2].open_alerts_by_severity
          end

          # with feature filter
          repo_ids_by_feature = {
            dependabot_alerts: [@cs_repo, @dbot_repo, @ss_repo, @mixed_repo].map(&:id),
            code_scanning: [@cs_repo, @dbot_repo, @ss_repo, @mixed_repo].map(&:id),
            secret_scanning: [@cs_repo, @dbot_repo, @ss_repo, @mixed_repo].map(&:id),
          }
          StatsDataQuery.for_organization(current_user: @org1_owner, user_session: @user_session, organization: @org1, parser: new_parser("code-scanning-alerts:>0"), repo_ids_by_feature: repo_ids_by_feature).run.tap do |result|
            assert_stats_structure result

            # Dependabot alerts
            assert_equal 1, result[0].affected_repo_count
            assert_equal 1, result[0].open_alerts_count
            assert_equal 2, result[0].total_repo_count
            assert_equal [:critical], result[0].open_alerts_by_severity.keys
            assert_equal 1, result[0].open_alerts_by_severity[:critical]

            # Code Scanning alerts
            assert_equal 2, result[1].affected_repo_count
            assert_equal 29, result[1].open_alerts_count
            assert_equal 2, result[1].total_repo_count
            assert_equal [:critical, :high, :medium, :low, :informational], result[1].open_alerts_by_severity.keys
            assert_equal 1, result[1].open_alerts_by_severity[:critical]
            assert_equal 2, result[1].open_alerts_by_severity[:high]
            assert_equal 4, result[1].open_alerts_by_severity[:medium]
            assert_equal 4, result[1].open_alerts_by_severity[:low]
            assert_equal 18, result[1].open_alerts_by_severity[:informational]

            # Secret Scanning alerts
            assert_equal 0, result[2].affected_repo_count
            assert_equal 0, result[2].open_alerts_count
            assert_equal 2, result[2].total_repo_count
            assert_empty result[2].open_alerts_by_severity
          end

          # all filter
          StatsDataQuery.for_organization(current_user: @org1_owner, user_session: @user_session, organization: @org1, parser: new_parser, repo_ids_by_feature: {}).run.tap do |result|
            assert_stats_structure result

            # everything filtered out; no results
            result.each do |r|
              assert_equal 0, r.affected_repo_count
              assert_equal 0, r.open_alerts_count
              assert_equal 0, r.total_repo_count
              assert_empty r.open_alerts_by_severity
            end
          end
        end

        context "for businesses with enterprise managed users on Dotcom", skip_enterprise: true do
          test "includes EMU-owned repos" do
            # query as business owner
            result = new_query(user: @mt_owner, scope: @mt_biz, organizations: [@mt_org]).run
            assert_stats_structure result

            # Dependabot alerts -- not yet visible on security center for EMU-owned repos
            assert_equal 0, result[0].affected_repo_count
            assert_equal 0, result[0].open_alerts_count
            assert_equal 6, result[0].total_repo_count
            assert_empty result[0].open_alerts_by_severity

            # Code Scanning alerts -- not yet supported for EMU-owned repos
            assert_equal 0, result[1].affected_repo_count
            assert_equal 0, result[1].open_alerts_count
            assert_equal 6, result[1].total_repo_count
            assert_empty result[1].open_alerts_by_severity

            # Secret Scanning alerts
            assert_equal 4, result[2].affected_repo_count
            assert_equal 10, result[2].open_alerts_count
            assert_equal 6, result[2].total_repo_count
            assert_empty result[2].open_alerts_by_severity
          end

          test "includes EMU-owned repos if user is an enterprise security manager" do
            # query as enterprise security manager
            result = new_query(user: @enterprise_security_manager, scope: @mt_biz, organizations: [@mt_org]).run
            assert_stats_structure result

            # Dependabot alerts -- not yet visible on security center for EMU-owned repos
            assert_equal 0, result[0].affected_repo_count
            assert_equal 0, result[0].open_alerts_count
            assert_equal 6, result[0].total_repo_count
            assert_empty result[0].open_alerts_by_severity

            # Code Scanning alerts -- not yet supported for EMU-owned repos
            assert_equal 0, result[1].affected_repo_count
            assert_equal 0, result[1].open_alerts_count
            assert_equal 6, result[1].total_repo_count
            assert_empty result[1].open_alerts_by_severity

            # Secret Scanning alerts
            assert_equal 4, result[2].affected_repo_count
            assert_equal 10, result[2].open_alerts_count
            assert_equal 6, result[2].total_repo_count
            assert_empty result[2].open_alerts_by_severity
          end

          test "excludes EMU-owned repos if the user is not an owner of the business" do
            result = new_query(user: @mt_user, scope: @mt_biz, organizations: [@mt_org]).run
            assert_stats_structure result

            ## Only results for @mt_org

            # Dependabot alerts -- not yet visible on security center for EMU-owned repos
            assert_equal 0, result[0].affected_repo_count
            assert_equal 0, result[0].open_alerts_count
            assert_equal 2, result[0].total_repo_count
            assert_empty result[0].open_alerts_by_severity

            # Code Scanning alerts -- not yet supported for EMU-owned repos
            assert_equal 0, result[1].affected_repo_count
            assert_equal 0, result[1].open_alerts_count
            assert_equal 2, result[1].total_repo_count
            assert_empty result[1].open_alerts_by_severity

            # Secret Scanning alerts
            assert_equal 1, result[2].affected_repo_count
            assert_equal 4, result[2].open_alerts_count
            assert_equal 2, result[2].total_repo_count
            assert_empty result[2].open_alerts_by_severity
          end

          test "excludes EMU-owned repos if GHAS is not purchased" do
            Business.any_instance.stubs(:advanced_security_purchased?).returns(false)

            # query as business owner
            result = new_query(user: @mt_owner, scope: @mt_biz, organizations: [@mt_org]).run
            assert_stats_structure result

            # Dependabot alerts -- not yet visible on security center for EMU-owned repos
            assert_equal 0, result[0].affected_repo_count
            assert_equal 0, result[0].open_alerts_count
            assert_equal 2, result[0].total_repo_count
            assert_empty result[0].open_alerts_by_severity

            # Code Scanning alerts -- not yet supported for EMU-owned repos
            assert_equal 0, result[1].affected_repo_count
            assert_equal 0, result[1].open_alerts_count
            assert_equal 2, result[1].total_repo_count
            assert_empty result[1].open_alerts_by_severity

            # Secret Scanning alerts
            assert_equal 1, result[2].affected_repo_count
            assert_equal 4, result[2].open_alerts_count
            assert_equal 2, result[2].total_repo_count
            assert_empty result[2].open_alerts_by_severity
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
                result = new_query(user: @mt_owner, scope: @mt_biz, organizations: [@mt_org], query_string: query_string).run
                assert_stats_structure result

                # Dependabot alerts
                result[0].tap do |dbot_stats|
                  assert_equal expected_dbot_stats[:affected_repo_count], dbot_stats.affected_repo_count
                  assert_equal expected_dbot_stats[:open_alerts_count], dbot_stats.open_alerts_count
                  assert_equal expected_dbot_stats[:total_repo_count], dbot_stats.total_repo_count
                  assert_equal expected_dbot_stats[:open_alerts_by_severity].keys, dbot_stats.open_alerts_by_severity.keys
                  expected_dbot_stats[:open_alerts_by_severity].each do |severity, count|
                    assert_equal count, dbot_stats.open_alerts_by_severity[severity]
                  end
                end

                # Code Scanning alerts
                result[1].tap do |cs_stats|
                  assert_equal expected_cs_stats[:affected_repo_count], cs_stats.affected_repo_count
                  assert_equal expected_cs_stats[:open_alerts_count], cs_stats.open_alerts_count
                  assert_equal expected_cs_stats[:total_repo_count], cs_stats.total_repo_count
                  assert_equal expected_cs_stats[:open_alerts_by_severity].keys, cs_stats.open_alerts_by_severity.keys
                  expected_cs_stats[:open_alerts_by_severity].each do |severity, count|
                    assert_equal count, cs_stats.open_alerts_by_severity[severity]
                  end
                end

                # Secret Scanning alerts
                result[2].tap do |ss_stats|
                  assert_equal expected_ss_stats[:affected_repo_count], ss_stats.affected_repo_count
                  assert_equal expected_ss_stats[:open_alerts_count], ss_stats.open_alerts_count
                  assert_equal expected_ss_stats[:total_repo_count], ss_stats.total_repo_count
                  assert_empty ss_stats.open_alerts_by_severity
                end
              end
            end
          end
        end

        context "for businesses without enterprise managed users on Dotcom", skip_enterprise: true do
          test "does not include user-owned repos" do
            result = new_query(scope: @business, organizations: [@org1]).run

            assert_stats_structure result

            # Dependabot alerts
            assert_equal 2, result[0].affected_repo_count
            assert_equal 8, result[0].open_alerts_count
            assert_equal 5, result[0].total_repo_count
            assert_equal [:critical, :high, :moderate, :low], result[0].open_alerts_by_severity.keys
            assert_equal 4, result[0].open_alerts_by_severity[:critical]
            assert_equal 2, result[0].open_alerts_by_severity[:high]
            assert_equal 1, result[0].open_alerts_by_severity[:moderate]
            assert_equal 1, result[0].open_alerts_by_severity[:low]

            # Code Scanning alerts
            assert_equal 2, result[1].affected_repo_count
            assert_equal 29, result[1].open_alerts_count
            assert_equal 5, result[1].total_repo_count
            assert_equal [:critical, :high, :medium, :low, :informational], result[1].open_alerts_by_severity.keys
            assert_equal 1, result[1].open_alerts_by_severity[:critical]
            assert_equal 2, result[1].open_alerts_by_severity[:high]
            assert_equal 4, result[1].open_alerts_by_severity[:medium]
            assert_equal 4, result[1].open_alerts_by_severity[:low]
            assert_equal 18, result[1].open_alerts_by_severity[:informational]

            # Secret Scanning alerts
            assert_equal 1, result[2].affected_repo_count
            assert_equal 3, result[2].open_alerts_count
            assert_equal 5, result[2].total_repo_count
            assert_empty result[2].open_alerts_by_severity
          end
        end

        context "for businesses with user-owned repositories on GHES", enterprise_only: true do
          test "includes user-owned repos if feature flag is enabled" do
            GitHub.stubs(:security_center_for_emus_enabled?).returns(true)

            result = new_query(scope: @business, organizations: [@org1]).run

            assert_stats_structure result

            # Dependabot alerts -- not yet visible on security center for EMU-owned repos
            assert_equal 2, result[0].affected_repo_count
            assert_equal 8, result[0].open_alerts_count
            assert_equal 7, result[0].total_repo_count
            assert_equal [:critical, :high, :moderate, :low], result[0].open_alerts_by_severity.keys
            assert_equal 4, result[0].open_alerts_by_severity[:critical]
            assert_equal 2, result[0].open_alerts_by_severity[:high]
            assert_equal 1, result[0].open_alerts_by_severity[:moderate]
            assert_equal 1, result[0].open_alerts_by_severity[:low]

            # Code Scanning alerts -- not yet supported for EMU-owned repos
            assert_equal 2, result[1].affected_repo_count
            assert_equal 29, result[1].open_alerts_count
            assert_equal 7, result[1].total_repo_count
            assert_equal [:critical, :high, :medium, :low, :informational], result[1].open_alerts_by_severity.keys
            assert_equal 1, result[1].open_alerts_by_severity[:critical]
            assert_equal 2, result[1].open_alerts_by_severity[:high]
            assert_equal 4, result[1].open_alerts_by_severity[:medium]
            assert_equal 4, result[1].open_alerts_by_severity[:low]
            assert_equal 18, result[1].open_alerts_by_severity[:informational]

            # Secret Scanning alerts
            assert_equal 2, result[2].affected_repo_count
            assert_equal 6, result[2].open_alerts_count
            assert_equal 7, result[2].total_repo_count
            assert_empty result[2].open_alerts_by_severity
          end

          test "excludes user-owned repos if GHAS is not purchased" do
            GitHub.stubs(:security_center_for_emus_enabled?).returns(true)
            Business.any_instance.stubs(:advanced_security_purchased?).returns(false)

            result = new_query(scope: @business, organizations: [@org1]).run

            assert_equal 1, result.length # limited security center, only dependabot alerts visible

            # Dependabot alerts -- not yet visible on security center for EMU-owned repos
            assert_equal 2, result[0].affected_repo_count
            assert_equal 8, result[0].open_alerts_count
            assert_equal 5, result[0].total_repo_count
            assert_equal [:critical, :high, :moderate, :low], result[0].open_alerts_by_severity.keys
            assert_equal 4, result[0].open_alerts_by_severity[:critical]
            assert_equal 2, result[0].open_alerts_by_severity[:high]
            assert_equal 1, result[0].open_alerts_by_severity[:moderate]
            assert_equal 1, result[0].open_alerts_by_severity[:low]
          end

          test "excludes user-owned repos if feature flag is not enabled" do
            GitHub.stubs(:security_center_for_emus_enabled?).returns(false)

            result = new_query(scope: @business, organizations: [@org1]).run

            assert_stats_structure result

            # Dependabot alerts -- not yet visible on security center for EMU-owned repos
            assert_equal 2, result[0].affected_repo_count
            assert_equal 8, result[0].open_alerts_count
            assert_equal 5, result[0].total_repo_count
            assert_equal [:critical, :high, :moderate, :low], result[0].open_alerts_by_severity.keys
            assert_equal 4, result[0].open_alerts_by_severity[:critical]
            assert_equal 2, result[0].open_alerts_by_severity[:high]
            assert_equal 1, result[0].open_alerts_by_severity[:moderate]
            assert_equal 1, result[0].open_alerts_by_severity[:low]

            # Code Scanning alerts -- not yet supported for EMU-owned repos
            assert_equal 2, result[1].affected_repo_count
            assert_equal 29, result[1].open_alerts_count
            assert_equal 5, result[1].total_repo_count
            assert_equal [:critical, :high, :medium, :low, :informational], result[1].open_alerts_by_severity.keys
            assert_equal 1, result[1].open_alerts_by_severity[:critical]
            assert_equal 2, result[1].open_alerts_by_severity[:high]
            assert_equal 4, result[1].open_alerts_by_severity[:medium]
            assert_equal 4, result[1].open_alerts_by_severity[:low]
            assert_equal 18, result[1].open_alerts_by_severity[:informational]

            # Secret Scanning alerts
            assert_equal 1, result[2].affected_repo_count
            assert_equal 3, result[2].open_alerts_count
            assert_equal 5, result[2].total_repo_count
            assert_empty result[2].open_alerts_by_severity
          end
        end

        context "executes expected number of queries" do
          test "when user has access to all repositories" do
            assert_query_count(3) do
              new_query.run
            end
          end

          test "when user has access to subset of repositories" do
            repo_ids_by_feature = {
              dependabot_alerts: [@dbot_repo].map(&:id),
              code_scanning: [@cs_repo].map(&:id),
              secret_scanning: [@ss_repo].map(&:id),
            }
            # repo count+status+severity per-feature (6)
            assert_query_count(7) do
              query = StatsDataQuery.for_organization(current_user: @org1_owner, user_session: @user_session, organization: @org1, parser: new_parser, repo_ids_by_feature: repo_ids_by_feature)
              query.run
            end
          end
        end

        test "only returns data for security features enabled for the instance" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          assert_query_count(3) do
            assert_equal [:dependabot_alerts, :code_scanning, :secret_scanning], new_query.run.map(&:feature_type)
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: false,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          assert_query_count(2) do
            assert_equal [:dependabot_alerts, :secret_scanning], new_query.run.map(&:feature_type)
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: false,
            dependabot_alerts_enabled_for_instance?: true,
          )

          assert_query_count(2) do
            assert_equal [:dependabot_alerts, :code_scanning], new_query.run.map(&:feature_type)
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: false,
          )

          assert_query_count(2) do
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
              result = new_query(query_string: query_string).run

              assert_stats_structure result

              # Dependabot alerts
              result[0].tap do |dbot_stats|
                assert_equal expected_dbot_stats[:affected_repo_count], dbot_stats.affected_repo_count
                assert_equal expected_dbot_stats[:open_alerts_count], dbot_stats.open_alerts_count
                assert_equal expected_dbot_stats[:total_repo_count], dbot_stats.total_repo_count
                assert_equal expected_dbot_stats[:open_alerts_by_severity].keys, dbot_stats.open_alerts_by_severity.keys
                expected_dbot_stats[:open_alerts_by_severity].each do |severity, count|
                  assert_equal count, dbot_stats.open_alerts_by_severity[severity]
                end
              end

              # Code Scanning alerts
              result[1].tap do |cs_stats|
                assert_equal expected_cs_stats[:affected_repo_count], cs_stats.affected_repo_count
                assert_equal expected_cs_stats[:open_alerts_count], cs_stats.open_alerts_count
                assert_equal expected_cs_stats[:total_repo_count], cs_stats.total_repo_count
                assert_equal expected_cs_stats[:open_alerts_by_severity].keys, cs_stats.open_alerts_by_severity.keys
                expected_cs_stats[:open_alerts_by_severity].each do |severity, count|
                  assert_equal count, cs_stats.open_alerts_by_severity[severity]
                end
              end

              # Secret Scanning alerts
              result[2].tap do |ss_stats|
                assert_equal expected_ss_stats[:affected_repo_count], ss_stats.affected_repo_count
                assert_equal expected_ss_stats[:open_alerts_count], ss_stats.open_alerts_count
                assert_equal expected_ss_stats[:total_repo_count], ss_stats.total_repo_count
                assert_empty ss_stats.open_alerts_by_severity
              end
            end
          end
        end
      end

      private

      def new_query(user: @org1_owner, scope: @org1, query_string: "", organizations: nil)
        if scope.is_a?(Organization)
          StatsDataQuery.for_organization(current_user: user, user_session: @user_session, organization: scope, parser: new_parser(query_string))
        else
          StatsDataQuery.for_organizations(current_user: user, user_session: @user_session, business: scope, organizations: organizations, parser: new_parser(query_string))
        end
      end

      def new_parser(query_string = "")
        ::Search::Queries::SecurityCenter::RiskQueryParser.new(query_string)
      end

      def create_repo(name, owner:, dbot_counts: {}, cs_counts: {}, ss_counts: {})
        create(:private_repository, name: name, owner: owner).tap do |r|
          create(
            :repository_security_center_config,
            repository: r,
            ghas_enabled: true,
          )
          create_status(r, feature: :dependabot_alerts, count: dbot_counts.values.sum)
          dbot_counts.each do |severity, count|
            create_severity(r, feature: :dependabot_alerts, severity: severity, count: count)
          end
          create_status(r, feature: :code_scanning, count: cs_counts.values.sum)
          cs_counts.each do |severity, count|
            create_severity(r, feature: :code_scanning, severity: severity, count: count)
          end
          create_status(r, feature: :secret_scanning, count: ss_counts.values.sum)
          # secret scanning doesn't create severity records
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

      def create_severity(repo, feature:, severity:, count:)
        create(
          :security_center_alert_severity,
          repository: repo,
          feature_type: feature,
          severity: severity,
          alert_count: count
        )
      end

      def assert_stats_structure(result)
        assert_equal 3, result.length

        result[0].tap do |r|
          assert_equal :dependabot_alerts, r.feature_type
          assert_operator r.affected_repo_count, :>=, 0
          assert_operator r.open_alerts_count, :>=, 0
          assert_operator r.total_repo_count, :>=, 0
        end

        result[1].tap do |r|
          assert_equal :code_scanning, r.feature_type
          assert_operator r.affected_repo_count, :>=, 0
          assert_operator r.open_alerts_count, :>=, 0
          assert_operator r.total_repo_count, :>=, 0
        end

        result[2].tap do |r|
          assert_equal :secret_scanning, r.feature_type
          assert_operator r.affected_repo_count, :>=, 0
          assert_operator r.open_alerts_count, :>=, 0
          assert_operator r.total_repo_count, :>=, 0
        end
      end
    end
  end
end
