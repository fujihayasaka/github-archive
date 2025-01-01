# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Risk
    class ListQueryTest < GitHub::TestCase
      include GitHub::Memoizer
      include DogstatsTestHelpers
      include DuplicateQueryTestHelper

      RiskQueryParser = ::Search::Queries::SecurityCenter::RiskQueryParser

      SELECT_REPOSITORY_UNLOCKS_REGEX = /\ASELECT .* FROM `repository_unlocks`/

      fixtures do
        # Business
        GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
        @owner = create(:user)
        @owner_session = create(:user_session, user: @owner)
        @business = create(:global_business)

        # Orgs, repos, and teams
        @org1 = create(:business_plus_organization, business: @business, admin: @owner, name: "test-org-1").tap do |o|
          @cs_repo = create_repo("#{o}-cs-repo", owner: o, dbot_count: 0, cs_count: 1, ss_count: 0)
          @dbot_repo = create_repo("#{o}-dbot-repo", owner: o, dbot_count: 2, cs_count: 0, ss_count: 0)
          @ss_repo = create_repo("#{o}-ss-repo", owner: o,  dbot_count: 0, cs_count: 0, ss_count: 2)
          @mixed_repo = create_repo("#{o}-mixed-repo", owner: o,  dbot_count: 1, cs_count: 2, ss_count: 1)
          @no_alerts_repo = create_repo("#{o}-no-alerts-repo", owner: o,  dbot_count: 0, cs_count: 0, ss_count: 0)
          @user_ss_repo = create_repo("#{o}-user-ss-repo", owner: @owner, dbot_count: 0, cs_count: 0, ss_count: 1)
          @user_no_alerts_repo = create_repo("#{o}-user-no-alerts-repo", owner: @owner, dbot_count: 0, cs_count: 0, ss_count: 0)

          create(:team, name: "#{o}-mixed-repo-team", organization: o).tap { |team| team.add_repository(@mixed_repo, :admin) }

          create(:topic, name: "apples").tap { |t| create(:repository_topic, topic: t, repository: @cs_repo) }
          create(:topic, name: "oranges").tap { |t| create(:repository_topic, topic: t, repository: @dbot_repo) }
        end

        @org2 = create(:business_plus_organization, business: @business, admin: @owner, name: "test-org-2").tap do |o|
          create_repo("#{o}-repo", owner: o)
          create_repo("#{o}-repo-2", owner: o)
          create_repo("#{o}-repo-3", owner: o, archived: true)
        end

        unless GitHub.enterprise?
          @mt_user = create(:emu)
          @mt_biz = @mt_user.enterprise_managed_business
          @mt_biz_owner = @mt_biz.owners.first
          @mt_biz.add_owner(@mt_user, actor: nil)

          @mt_user.tap do |o|
            @mt_user_ss_repo = create_repo("#{o}-mt-user-ss-repo", owner: @mt_user, dbot_count: 0, cs_count: 0, ss_count: 1)
            @mt_user_no_alerts_repo = create_repo("#{o}-mt-user-no-alerts-repo", owner: @mt_user, dbot_count: 0, cs_count: 0, ss_count: 0)
          end

          @mt_org = create(:business_plus_organization, business: @mt_biz, admin: @mt_user, name: "test-org-mt").tap do |o|
            @mt_org_mixed_repo = create_repo("#{o}-mt-mixed-repo", owner: o, dbot_count: 1, cs_count: 2, ss_count: 1)
            @mt_org_ss_repo = create_repo("#{o}-mt-ss-repo", owner: o, dbot_count: 0, cs_count: 0, ss_count: 2)
            @mt_org_no_alerts_repo = create_repo("#{o}-mt-no-alerts-repo", owner: o, dbot_count: 0, cs_count: 0, ss_count: 0)
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
          [["repo", "NOT mixed"], 6],
          [["archived:false", "-archived:true"], 6],
          [["code-scanning-alerts:enabled", "-code-scanning-alerts:disabled"], 6],
          [["dependabot-alerts:enabled", "-dependabot-alerts:disabled"], 6],
          [["is:private", "-is:public"], 6],
          [["repo:test-org-1-mixed-repo", "-repo:whatever"], 6],
          [["repo:test-org-1/test-org-1-mixed-repo", "-repo:org/whatever"], 7],
          [["owner:test-org-2", "-owner:whatever2"], 6],
          [["owner-type:organization", "-owner-type:user"], 6],
          [["secret-scanning-alerts:enabled", "-secret-scanning-alerts:disabled"], 6],
          [["has-severity:medium", "-has-severity:low"], 6],
          [["sort:repos", "sort:last-updated-asc", "sort:code-scanning", "sort:dependabot", "sort:secret-scanning"], 6],
          [["team:test-org-1-mixed-repo-team", "-team:test-org-1-mixed-repo-team"], 10],
          [["topic:apples", "-topic:oranges"], 8],
          [["props.custom:property", "-props.custom:property"], 6],
        ]
      end

      context "#run" do
        basic_filters_and_sort_with_query_counts.each do |filters, query_count|
          filters.each do |filter|
            test "basic test exercising filter: #{filter.start_with?("-") ? filter.sub("-", "negated ") : filter}" do
              assert_nothing_raised do
                assert_queries(count: query_count) do
                  ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: RiskQueryParser.new(filter)).perform
                end
              end
            end
          end
        end

        %w[code-scanning dependabot secret-scanning].each do |filter|
          test "results are properly sorted by number of #{filter}" do
            expected = @org1.repositories.to_a
            expected.sort_by! do |r|
              metadata = Repository.find_by!(repository_id: r.id)
              [
                metadata.feature_status_summary.send("#{filter}_alerts_total_count".underscore) || 0,
                metadata.pushed_at,
              ]
            end.reverse!

            assert_queries(count: 6) do
              ListQuery.for_organization(
                user: @owner,
                user_session: @owner_session,
                organization: @org1,
                parser: RiskQueryParser.new("sort:#{filter}"),
              ).perform
            end.tap do |result|
              list_items = result.list_items

              assert_equal expected.size, list_items.size
              assert_equal expected.map(&:name), list_items.map { |r| r.repo_metadata.name }, "first repo out of order expected: #{expected.map(&:name)} got: #{list_items.map { |r| r.repo_metadata.name }}"
            end
          end
        end

        test "basic test exercising all filters at once" do
          all_filters = self.class.basic_filters_and_sort_with_query_counts.map(&:first).flatten.join(" ")
          parser = RiskQueryParser.new(all_filters)

          # Make sure we're using all qualifiers, plus unqualified text, plus a repo with org prefixed
          assert_equal RiskQueryParser::QUALIFIERS.size + 2, self.class.basic_filters_and_sort_with_query_counts.size

          assert_nothing_raised do
            assert_queries(count: 15) do
              ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: parser).perform
            end
          end
        end

        test "returns results only for the provided organization" do
          assert_queries(count: 6) do
            ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: RiskQueryParser.new("")).perform
          end.tap do |result|
            list_items = result.list_items

            assert_equal @org1.repositories.size, list_items.size
            assert_same_elements \
              @org1.repositories.map(&:name),
              list_items.map { |r| r.repo_metadata.name }
          end

          assert_queries(count: 6) do
            ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org2, parser: RiskQueryParser.new("")).perform
          end.tap do |result|
            list_items = result.list_items

            assert_equal @org2.repositories.size, list_items.size
            assert_same_elements \
              @org2.repositories.map(&:name),
              list_items.map { |r| r.repo_metadata.name }
          end
        end

        context "for businesses with enterprise managed users on Dotcom", skip_enterprise: true do
          context "includes EMU-owned repos if feature flag is enabled" do
            test "as business owner with own repos" do
              assert_queries(count: 13) do
                assert_queries_matching SELECT_REPOSITORY_UNLOCKS_REGEX, 0 do
                  ListQuery.for_business(user: @mt_user, business: @mt_biz, parser: RiskQueryParser.new(""), organizations: {
                    code_scanning: [@mt_org],
                    dependabot_alerts: [@mt_org],
                    secret_scanning: [@mt_org],
                  }).perform
                end
              end.tap do |result|
                list_items = result.list_items

                expected_count = @mt_org.repositories.size + @mt_user.repositories.size
                expected_repository_names = @mt_org.repositories.map(&:full_name) + @mt_user.repositories.map(&:full_name)

                assert_equal expected_count, list_items.size
                assert_same_elements \
                expected_repository_names,
                  list_items.map { |r| r.repo_metadata.name }
              end
            end

            test "as business owner with repos owned by another user" do
              # Extra queries to check if @mt_biz_owner has unlocked repos belonging to @mt_user
              assert_queries(count: 14) do
                assert_queries_matching SELECT_REPOSITORY_UNLOCKS_REGEX, 1 do
                  ListQuery.for_business(user: @mt_biz_owner, business: @mt_biz, parser: RiskQueryParser.new(""), organizations: {
                    code_scanning: [@mt_org],
                    dependabot_alerts: [@mt_org],
                    secret_scanning: [@mt_org],
                  }).perform
                end
              end.tap do |result|
                list_items = result.list_items

                expected_count = @mt_org.repositories.size + @mt_user.repositories.size
                expected_repository_names = @mt_org.repositories.map(&:full_name) + @mt_user.repositories.map(&:full_name)

                assert_equal expected_count, list_items.size
                assert_same_elements \
                expected_repository_names,
                  list_items.map { |r| r.repo_metadata.name }
              end
            end

            test "as an enterprise security manager with repos owned by another user" do
              assert_queries(count: 14) do
                assert_queries_matching SELECT_REPOSITORY_UNLOCKS_REGEX, 1 do
                  ListQuery.for_business(user: @enterprise_security_manager, business: @mt_biz, parser: RiskQueryParser.new(""), organizations: {
                    code_scanning: [@mt_org],
                    dependabot_alerts: [@mt_org],
                    secret_scanning: [@mt_org],
                  }).perform
                end
              end.tap do |result|
                list_items = result.list_items

                expected_count = @mt_org.repositories.size + @mt_user.repositories.size
                expected_repository_names = @mt_org.repositories.map(&:full_name) + @mt_user.repositories.map(&:full_name)

                assert_equal expected_count, list_items.size
                assert_same_elements \
                expected_repository_names,
                  list_items.map { |r| r.repo_metadata.name }
              end
            end
          end

          test "excludes EMU-owned repos if GHAS is not purchased" do
            Business.any_instance.stubs(:advanced_security_purchased?).returns(false)

            assert_queries(count: 10) do
              ListQuery.for_business(user: @mt_user, business: @mt_biz, parser: RiskQueryParser.new(""), organizations: {
                code_scanning: [@mt_org],
                dependabot_alerts: [@mt_org],
                secret_scanning: [@mt_org],
              }).perform
            end.tap do |result|
              list_items = result.list_items

              expected_count = @mt_org.repositories.size
              expected_repository_names = @mt_org.repositories.map(&:full_name)

              assert_equal expected_count, list_items.size
              assert_same_elements \
              expected_repository_names,
                list_items.map { |r| r.repo_metadata.name }
            end
          end
        end

        context "for businesses without enterprise managed users on Dotcom", skip_enterprise: true do
          test "does not include user-owned repos" do
            assert_queries(count: 10) do
              ListQuery.for_business(user: @owner, business: @business, parser: RiskQueryParser.new(""), organizations: {
                code_scanning: [@org1, @org2],
                dependabot_alerts: [@org1, @org2],
                secret_scanning: [@org1, @org2],
              }).perform
            end.tap do |result|
              list_items = result.list_items

              expected_count = @org1.repositories.size + @org2.repositories.size
              expected_repository_names = @org1.repositories.map(&:full_name) + @org2.repositories.map(&:full_name)

              assert_equal expected_count, list_items.size
              assert_same_elements \
              expected_repository_names,
                list_items.map { |r| r.repo_metadata.name }
            end
          end
        end

        context "for businesses with user-owned repositories on GHES", enterprise_only: true do
          context "includes user-owned repos if feature flag is enabled" do
            test "for business owner with own repos" do
              GitHub.stubs(:security_center_for_emus_enabled?).returns(true)

              @business.add_owner(@owner, actor: nil)

              assert_queries(count: 12) do
                assert_queries_matching SELECT_REPOSITORY_UNLOCKS_REGEX, 0 do
                  ListQuery.for_business(user: @owner, business: @business, parser: RiskQueryParser.new(""), organizations: {
                    code_scanning: [@org1, @org2],
                    dependabot_alerts: [@org1, @org2],
                    secret_scanning: [@org1, @org2],
                  }).perform
                end
              end.tap do |result|
                list_items = result.list_items

                expected_count = @org1.repositories.size + @org2.repositories.size + @owner.repositories.size
                expected_repository_names = @org1.repositories.map(&:full_name) + @org2.repositories.map(&:full_name) + @owner.repositories.map(&:full_name)

                assert_equal expected_count, list_items.size
                assert_same_elements \
                expected_repository_names,
                  list_items.map { |r| r.repo_metadata.name }
              end
            end

            test "for business owner with repos owned by another user" do
              GitHub.stubs(:security_center_for_emus_enabled?).returns(true)

              other_biz_owner = create(:user)
              @business.add_owner(other_biz_owner, actor: nil)

              assert_queries(count: 13) do
                assert_queries_matching SELECT_REPOSITORY_UNLOCKS_REGEX, 1 do
                  ListQuery.for_business(user: other_biz_owner, business: @business, parser: RiskQueryParser.new(""), organizations: {
                    code_scanning: [@org1, @org2],
                    dependabot_alerts: [@org1, @org2],
                    secret_scanning: [@org1, @org2],
                  }).perform
                end
              end.tap do |result|
                list_items = result.list_items

                expected_count = @org1.repositories.size + @org2.repositories.size + @owner.repositories.size
                expected_repository_names = @org1.repositories.map(&:full_name) + @org2.repositories.map(&:full_name) + @owner.repositories.map(&:full_name)

                assert_equal expected_count, list_items.size
                assert_same_elements \
                expected_repository_names,
                  list_items.map { |r| r.repo_metadata.name }
              end
            end
          end

          test "excludes user-owned repos if GHAS is not purchased" do
            GitHub.stubs(:security_center_for_emus_enabled?).returns(true)
            Business.any_instance.stubs(:advanced_security_purchased?).returns(false)

            assert_queries(count: 10) do
              ListQuery.for_business(user: @owner, business: @business, parser: RiskQueryParser.new(""), organizations: {
                code_scanning: [@org1, @org2],
                dependabot_alerts: [@org1, @org2],
                secret_scanning: [@org1, @org2],
              }).perform
            end.tap do |result|
              list_items = result.list_items

              expected_count = @org1.repositories.size + @org2.repositories.size
              expected_repository_names = @org1.repositories.map(&:full_name) + @org2.repositories.map(&:full_name)

              assert_equal expected_count, list_items.size
              assert_same_elements \
              expected_repository_names,
                list_items.map { |r| r.repo_metadata.name }
            end
          end

          test "excludes user-owned repos if feature flag is disabled" do
            GitHub.stubs(:security_center_for_emus_enabled?).returns(false)

            assert_queries(count: 10) do
              ListQuery.for_business(user: @owner, business: @business, parser: RiskQueryParser.new(""), organizations: {
                code_scanning: [@org1, @org2],
                dependabot_alerts: [@org1, @org2],
                secret_scanning: [@org1, @org2],
              }).perform
            end.tap do |result|
              list_items = result.list_items

              expected_count = @org1.repositories.size + @org2.repositories.size
              expected_repository_names = @org1.repositories.map(&:full_name) + @org2.repositories.map(&:full_name)

              assert_equal expected_count, list_items.size
              assert_same_elements \
              expected_repository_names,
                list_items.map { |r| r.repo_metadata.name }
            end
          end
        end

        test "returns results limited by provided organizations" do
          features = [:code_scanning, :dependabot_alerts, :secret_scanning]
          test_matrix = features.product(features).map(&:uniq).push(features)
          test_matrix.each do |features|
            ListQuery.for_business(
              user: @owner,
              business: @business,
              parser: RiskQueryParser.new("repo:test-org-1/test-org-1-mixed-repo"),
              organizations: Hash.new([]).merge(features.product([[@org1]]).to_h),
            ).perform.tap do |result|
              list_items = result.list_items

              assert_equal 1, result.list_items.size
              assert_same_elements features, result.list_items.first.repo_alert_count_map.keys, "expected: #{features} got: #{result.list_items.first.repo_alert_count_map.keys}"
            end
          end
        end

        test "returns results limited by provided repository ids" do
          # no filter
          expected = [@cs_repo, @dbot_repo, @ss_repo, @mixed_repo, @no_alerts_repo]
          assert_queries(count: 6) do
            ListQuery.for_organization(
              user: @owner,
              user_session: @owner_session,
              organization: @org1,
              parser: RiskQueryParser.new(""),
              repo_ids_by_feature: nil
            ).perform
          end.tap do |result|
            list_items = result.list_items

            assert_equal expected.size, list_items.size
            assert_same_elements \
              expected.map(&:name),
              list_items.map { |r| r.repo_metadata.name }
          end

          # partial filter
          expected = [@cs_repo, @dbot_repo, @ss_repo]
          repo_ids_by_feature = RepositorySecurityCenterStatus.primary_feature_types.each_with_object({}) do |feature, h|
            h[feature] = expected.map(&:id)
          end
          assert_queries(count: 6) do
            ListQuery.for_organization(
              user: @owner,
              user_session: @owner_session,
              organization: @org1,
              parser: RiskQueryParser.new(""),
              repo_ids_by_feature: repo_ids_by_feature
            ).perform
          end.tap do |result|
            list_items = result.list_items

            assert_equal expected.size, list_items.size
            assert_same_elements \
              expected.map(&:name),
              list_items.map { |r| r.repo_metadata.name }
          end

          # mixed access
          expected = [@cs_repo, @dbot_repo]
          repo_ids_by_feature = {
            dependabot_alerts: [@cs_repo, @dbot_repo].map(&:id),
            code_scanning: [@cs_repo].map(&:id),
            secret_scanning: [],
          }
          assert_queries(count: 6) do
            ListQuery.for_organization(
              user: @owner,
              user_session: @owner_session,
              organization: @org1,
              parser: RiskQueryParser.new(""),
              repo_ids_by_feature: repo_ids_by_feature
            ).perform
          end.tap do |result|
            list_items = result.list_items

            assert_equal expected.size, list_items.size
            assert_same_elements \
              expected.map(&:name),
              list_items.map { |r| r.repo_metadata.name }
          end

          # with feature filter
          expected = [@cs_repo, @mixed_repo]
          repo_ids_by_feature = {
            dependabot_alerts: [@cs_repo, @dbot_repo, @ss_repo, @mixed_repo].map(&:id),
            code_scanning: [@cs_repo, @dbot_repo, @ss_repo, @mixed_repo].map(&:id),
            secret_scanning: [@cs_repo, @dbot_repo, @ss_repo, @mixed_repo].map(&:id),
          }
          assert_queries(count: 6) do
            ListQuery.for_organization(
              user: @owner,
              user_session: @owner_session,
              organization: @org1,
              parser: RiskQueryParser.new("code-scanning-alerts:>0"),
              repo_ids_by_feature: repo_ids_by_feature
            ).perform
          end.tap do |result|
            list_items = result.list_items

            assert_equal expected.size, list_items.size
            assert_same_elements \
              expected.map(&:name),
              list_items.map { |r| r.repo_metadata.name }
          end

          # all filter
          expected = []
          assert_queries(count: 1) do
            ListQuery.for_organization(
              user: @owner,
              user_session: @owner_session,
              organization: @org1,
              parser: RiskQueryParser.new(""),
              repo_ids_by_feature: {}
            ).perform
          end.tap do |result|
            assert_empty result.list_items
          end
        end

        test "limits results returned by page_size" do
          parser = RiskQueryParser.new("sort:repos")
          repo_count = @org1.repositories.size

          # page_size less than total results
          # 'will_paginate' adds an extra query to get the count for 'total_entries' since the result count equals the page size
          assert_queries(count: 6) do
            ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: parser).perform(page_size: 2)
          end.tap do |result|
            list_items = result.list_items

            assert_equal 2, list_items.size
            assert_equal @org1.repositories.map(&:name).sort.first(2), list_items.map { |r| r.repo_metadata.name }
          end

          # page_size equal to total results
          # 'will_paginate' adds an extra query to get the count for 'total_entries' since the result count equals the page size
          assert_queries(count: 6) do
            ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: parser).perform(page_size: repo_count)
          end.tap do |result|
            list_items = result.list_items

            assert_equal repo_count, list_items.size
            assert_equal @org1.repositories.map(&:name).sort, list_items.map { |r| r.repo_metadata.name }
          end

          # page_size greater than total results
          # 'will_paginate' knows it doesn't need an extra query to get the count for 'total_entries' since there are fewer results than the page size
          assert_queries(count: 6) do
            ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: parser).perform(page_size: repo_count + 1)
          end.tap do |result|
            list_items = result.list_items

            assert_equal repo_count, list_items.size
            assert_equal repo_count, list_items.total_entries
            assert_equal 1, list_items.total_pages
            assert_equal @org1.repositories.map(&:name).sort, list_items.map { |r| r.repo_metadata.name }
          end
        end

        test "returns results for the requested page of data" do
          parser = RiskQueryParser.new("sort:repos")

          org = @org1
          page_size = 2
          expected_total_pages = (org.repositories.size.to_f / page_size).ceil

          # 'will_paginate' adds an extra query to get the count for 'total_entries' since the result count equals the page size
          assert_queries(count: 6) do
            ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: org, parser: parser).perform(page: 1, page_size:)
          end.tap do |result|
            list_items = result.list_items

            assert_equal page_size, list_items.size
            page_size.times do |i|
              assert_equal org.repositories.map(&:name).sort[i], list_items[i].repo_metadata.name
            end
          end

          # Whether 'will_paginate' adds an extra query to get the count for 'total_entries' depends on if the number of results equals the page size
          expected_results_count = (org.repositories.size % page_size).then { |n| n.zero? ? page_size : n }
          query_count = expected_results_count == page_size ? 7 : 6
          assert_queries(count: query_count) do
            ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: org, parser: parser).perform(page: expected_total_pages, page_size:)
          end.tap do |result|
            list_items = result.list_items

            assert_equal expected_results_count, list_items.size
            assert_equal expected_total_pages, list_items.total_pages
            assert_equal org.repositories.size, list_items.total_entries

            last_repos = org.repositories.map(&:name).sort.last(list_items.size)
            list_items.size.times do |i|
              assert_equal last_repos[i], list_items[i].repo_metadata.name
            end
          end

          # 'page' is beyond the total number of pages
          # Queries: 1: count by archived, 2: current page, 3: total_entries
          assert_queries(count: 1) do
            ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: org, parser: parser).perform(page: expected_total_pages + 1, page_size:)
          end.tap do |result|
            list_items = result.list_items

            assert_equal 0, list_items.size
          end
        end

        test "returns expected metadata for each repo" do
          assert_queries(count: 6) do
            ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: RiskQueryParser.new("")).perform
          end.tap do |result|
            list_items = result.list_items

            assert_equal list_items.map(&:repo_metadata).map(&:name).uniq.size, list_items.size
            assert_equal @org1.repositories.size, list_items.size
            list_items.each do |r|
              @org1.repositories.find_by!(name: r.repo_metadata.name).tap do |repo|
                assert_equal urls.repository_security_overview_path(repo.owner, repo), r.repo_metadata.href
                assert_equal repo.visibility, r.repo_metadata.visibility
                assert_equal UrlHelpers.security_center_risk_path(@org1, { query: "is:private" }), r.repo_metadata.visibility_href
                assert_equal repo.pushed_at, r.repo_metadata.updated_at
              end
            end
          end
        end

        context "for security features disabled at the instance level" do
          test "does not return results for dependabot" do
            SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(false)
            UrlHelpers.expects(:repository_alerts_path).never

            assert_queries(count: 6) do
              ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: RiskQueryParser.new("")).perform
            end.tap do |result|
              result.items.each do |r|
                assert_nil(r.repo_alert_count_map[:dependabot])
              end
            end
          end

          test "does not return results for code scanning" do
            SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(false)
            UrlHelpers.expects(:repository_code_scanning_results_path).never

            assert_queries(count: 6) do
              ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: RiskQueryParser.new("")).perform
            end.tap do |result|
              result.items.each do |r|
                assert_nil(r.repo_alert_count_map[:code_scanning])
              end
            end
          end

          test "does not return results for secret scanning" do
            SecurityCenter::SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(false)

            # We should not attempt to build the URL. If the feature is instance-disabled, the route doesn't actually get loaded.
            # https://github.com/github/security-center/issues/6633
            UrlHelpers.expects(:repository_token_scanning_results_path).never

            assert_queries(count: 6) do
              ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: RiskQueryParser.new("")).perform
            end.tap do |result|
              result.items.each do |r|
                assert_nil(r.repo_alert_count_map[:secret_scanning])
              end
            end
          end

          test "does not return results for any feature" do
            SecurityCenter::SecurityFeatures.stubs(
              dependabot_alerts_enabled_for_instance?: false,
              code_scanning_enabled_for_instance?: false,
              secret_scanning_enabled_for_instance?: false,
            )

            UrlHelpers.expects(:repository_alerts_path).never
            UrlHelpers.expects(:repository_code_scanning_results_path).never
            UrlHelpers.expects(:repository_token_scanning_results_path).never

            assert_queries(count: 0) do
              ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: RiskQueryParser.new("")).perform
            end.tap do |result|
              result.items.each do |r|
                assert_nil(r.repo_alert_count_map[:dependabot])
                assert_nil(r.repo_alert_count_map[:code_scanning])
                assert_nil(r.repo_alert_count_map[:secret_scanning])
              end
            end
          end
        end

        test "uses repo's root URL for temporary private forks" do
          owner = create(:user)
          org = create(:organization, admin: owner)

          GitHub.context.push(actor_id: owner.id) # Avoids `ActiveRecord::RecordInvalid: Validation failed: Updater must exist`
          advisory_repo = create_repo("#{org}-advisory-repo", owner: org, ss_count: 1)
          workspace_repo = create_workspace_repo(advisory_repo, actor: owner)

          assert_queries(count: 6) do
            ListQuery.for_organization(user: owner, user_session: @owner_session, organization: org, parser: RiskQueryParser.new("")).perform
          end.tap do |result|
            list_items = result.list_items

            assert_equal list_items.map(&:repo_metadata).map(&:name).uniq.size, list_items.size
            assert_equal org.repositories.size, list_items.size
            list_items.each do |r|
              metadata_name = r.repo_metadata.name
              expected = if metadata_name == workspace_repo.name
                urls.repository_path(org.display_login, metadata_name)
              else
                urls.repository_security_overview_path(org.display_login, metadata_name)
              end
              assert_equal expected, r.repo_metadata.href
            end
          end
        end

        test "returns expected alert counts for each repo and feature" do
          assert_queries(count: 6) do
            ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: RiskQueryParser.new("")).perform
          end.tap do |result|
            list_items = result.list_items

            assert_equal 5, @org1.repositories.size # Using this assertion as an indicator to update this test when the number of repos in the org changes

            assert list_items.map(&:repo_metadata).map(&:name).uniq.size == list_items.size
            list_items.each do |r|
              case r.repo_metadata.name
              when @cs_repo.name
                assert_nil(r.repo_alert_count_map[:dependabot_alerts])
                assert_equal 1, r.repo_alert_count_map[:code_scanning].alert_count
                assert_nil(r.repo_alert_count_map[:secret_scanning])
              when @dbot_repo.name
                assert_equal 2, r.repo_alert_count_map[:dependabot_alerts].alert_count
                assert_nil(r.repo_alert_count_map[:code_scanning])
                assert_nil(r.repo_alert_count_map[:secret_scanning])
              when @ss_repo.name
                assert_nil(r.repo_alert_count_map[:dependabot_alerts])
                assert_nil(r.repo_alert_count_map[:code_scanning])
                assert_equal 2, r.repo_alert_count_map[:secret_scanning].alert_count
              when @mixed_repo.name
                assert_equal 1, r.repo_alert_count_map[:dependabot_alerts].alert_count
                assert_equal 2, r.repo_alert_count_map[:code_scanning].alert_count
                assert_equal 1, r.repo_alert_count_map[:secret_scanning].alert_count
              when @no_alerts_repo.name
                assert_nil(r.repo_alert_count_map[:dependabot_alerts])
                assert_nil(r.repo_alert_count_map[:code_scanning])
                assert_nil(r.repo_alert_count_map[:secret_scanning])
              else
                raise "Unexpected repo #{r.repo_metadata.name}"
              end
            end
          end
        end

        test "emits access_violation metrics if out-of-scope repos are returned by the query" do
          # make the root query ignore its org_id filter
          Repository.stubs(:where).returns(Repository.all)

          assert_queries(count: 6) do
            ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: RiskQueryParser.new("")).perform
          end

          assert_dogstats_increment("security_center.access_violation", tags: ["feature:risk", "scope:organization"])
        end
      end

      context "telemetry" do
        test "includes each applied filter as tags" do
          query = "archived:false is:private repo:repo-name secret-scanning:>0"
          ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: RiskQueryParser.new(query)).perform

          assert_dogstats_distribution("security_center.risk_list_data_query.run.dist", tags: [
            "has_filter:by_archived",
            "has_filter:by_visibility",
            "has_filter:by_repository",
          ])
        end

        test "includes sort as tag" do
          query = "sort:dependabot"
          ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: RiskQueryParser.new(query)).perform

          assert_dogstats_distribution("security_center.risk_list_data_query.run.dist", tags: ["sort_by:dependabot"])
        end

        test "ignores invalid sort in tags" do
          query = "sort:invalid"
          ListQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: RiskQueryParser.new(query)).perform

          assert_dogstats_distribution("security_center.risk_list_data_query.run.dist", tags: ["sort_by:last-updated"])
        end
      end

      context "SELECT_REPOSITORY_UNLOCKS_REGEX" do
        test "matches expected queries" do
          assert SELECT_REPOSITORY_UNLOCKS_REGEX.match?("SELECT `repository_unlocks`.* FROM `repository_unlocks` WHERE `repository_unlocks`.`unlocked_by_id` = 247 AND `repository_unlocks`.`repository_id` = 250 ORDER BY created_at DESC LIMIT 1")
          assert SELECT_REPOSITORY_UNLOCKS_REGEX.match?("SELECT 1 AS one FROM `repository_unlocks` WHERE `repository_unlocks`.`revoked_by_id` IS NULL AND (`repository_unlocks`.`expires_at` > NOW()) AND `repository_unlocks`.`unlocked_by_id` = 247 AND `repository_unlocks`.`repository_id` = 250 LIMIT 1")
          refute SELECT_REPOSITORY_UNLOCKS_REGEX.match?("SELECT `businesses`.* FROM `businesses` WHERE `businesses`.`deleted_at` IS NULL AND `businesses`.`id` = 42")
        end
      end

      private

      sig { returns(UrlHelpers) }
      memoize def urls
        T.cast(Class.new { include UrlHelpers }.new, UrlHelpers)
      end

      def assert_queries(count: 0)
        result = T.let(nil, T.untyped)
        assert_query_count(count, ignore_feature_flags: true) do
          assert_duplicate_query_detection(ListQuery, 0) do
            result = yield
          end
        end

        result
      end

      def create_repo(name, owner:, visibility: :private, archived: false, dbot_count: 0, cs_count: 0, ss_count: 0)
        factory = case visibility
        when :private
          :private_repository
        when :public
          :repository
        when :internal
          :internal_repository
        end

        create(factory, name: name, owner: owner).tap do |r|
          r.set_archived if archived

          repository_metadata = create(:soa_repository, repository: r)

          create(
            :soa_feature_status,
            repository_metadata:,
            advanced_security_status: "ENABLED",
            dependabot_alerts_status: dbot_count > 0 ? "ENABLED" : "NOT_ENABLED",
            dependabot_alerts_total_count: dbot_count,
            code_scanning_alerts_status: cs_count > 0 ? "ENABLED" : "NOT_ENABLED",
            code_scanning_alerts_total_count: cs_count,
            code_scanning_alerts_medium_count: cs_count,
            secret_scanning_alerts_status: ss_count > 0 ? "ENABLED" : "NOT_ENABLED",
            secret_scanning_alerts_total_count: ss_count,
          )
        end
      end

      def create_workspace_repo(source_repo, actor:)
        GitHub.context.push(actor_id: actor.id) # Avoids `ActiveRecord::RecordInvalid: Validation failed: Updater must exist`
        advisory = create(:repository_advisory, repository: source_repo, author: actor)
        workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, actor).tap do |r|
          r.save!

          repository_metadata = create(:soa_repository, repository: r)

          create(
            :soa_feature_status,
            repository_metadata:,
            advanced_security_status: "ENABLED",
            dependabot_alerts_status: "ENABLED",
            dependabot_alerts_total_count: 1,
          )
        end
      end
    end
  end
end
