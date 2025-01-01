# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Coverage
    class CoverageListDataQueryTest < GitHub::TestCase
      include GitHub::Memoizer
      include DogstatsTestHelpers
      include DuplicateQueryTestHelper

      CoverageQueryParser = ::Search::Queries::SecurityCenter::CoverageQueryParser

      SELECT_REPOSITORY_UNLOCKS_REGEX = /\ASELECT .* FROM `repository_unlocks`/

      fixtures do
        # Business
        GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
        @business = create(:global_business)

        @owner = create(:user).tap do |u|
          create_repo("#{u}-ss-repo", owner: u,
            features: {
              secret_scanning: { status: :enrolled, count: 1 },
              secret_scanning_push_protection: { status: :enrolled, count: 0 },
            }
          )
          create_repo("#{u}-ss-pp-repo", owner: u,
            features: {
              secret_scanning: { status: :enrolled, count: 1 },
              secret_scanning_push_protection: { status: :enrolled, count: 1 },
            }
          )
        end

        # Orgs, repos, and teams
        @org1 = create(:business_plus_organization, business: @business, admin: @owner, name: "test-org-1").tap do |o|
          @cs_repo = create_repo("#{o}-cs-repo", owner: o,
            features: {
              code_scanning: { status: :enrolled, count: 1 },
              code_scanning_pr_reviews: { status: :enrolled, count: 0 },
            }
          )
          @dbot_repo = create_repo("#{o}-dbot-repo", owner: o,
            features: {
              dependabot_alerts: { status: :enrolled, count: 1 },
              dependabot_security_updates: { status: :enrolled, count: 0 },
            }
          )
          @ss_repo = create_repo("#{o}-ss-repo", owner: o,
            features: {
              secret_scanning: { status: :enrolled, count: 1 },
              secret_scanning_push_protection: { status: :enrolled, count: 0 },
            }
          )
          @mixed_repo = create_repo("#{o}-mixed-repo", owner: o,
            features: {
              code_scanning: { status: :enrolled, count: 0 },
              dependabot_alerts: { status: :enrolled, count: 0 },
              secret_scanning: { status: :enrolled, count: 0 },
            }
          )

          create(:team, name: "#{o}-mixed-repo-team", organization: o).tap { |team| team.add_repository(@mixed_repo, :admin) }
          create(:topic, name: "apples").tap { |t| create(:repository_topic, topic: t, repository: @cs_repo) }
          create(:topic, name: "oranges").tap { |t| create(:repository_topic, topic: t, repository: @dbot_repo) }
        end

        @org2 = create(:business_plus_organization, business: @business, admin: @owner, name: "test-org-2").tap do |o|
          create_repo("#{o}-repo", owner: o)
        end

        @org3 = create(:business_plus_organization, business: @business, name: "test-org-3").tap do |o|
          create_repo("#{o}-repo", owner: o,
            features: {
              code_scanning: { status: :enrolled, count: 0 },
              code_scanning_auto_codeql: { status: :enrolled, count: 0 },
            }
          )
          create_repo("#{o}-repo2", owner: o,
            features: {
              code_scanning: { status: :enrolled, count: 0 },
              code_scanning_auto_codeql: { status: :eligible, count: 0 },
            }
          )
        end

        unless GitHub.enterprise?
          @mt_user = create(:emu)
          @mt_biz = @mt_user.enterprise_managed_business
          @mt_biz_owner = @mt_biz.owners.first

          @mt_user.tap do |o|
            @mt_user_ss_repo = create_repo("#{o}-mt-user-ss-repo", owner: @mt_user,
              features: {
                secret_scanning: { status: :enrolled, count: 1 },
                secret_scanning_push_protection: { status: :enrolled, count: 0 },
              })
            @mt_user_no_alerts_repo = create_repo("#{o}-mt-user-no-features-repo", owner: @mt_user, features: {})
          end

          @mt_org = create(:business_plus_organization, business: @mt_biz, admin: @mt_user, name: "mt-org-1").tap do |o|
            @mt_org_mixed_repo = create_repo("#{o}-mt-org-mixed-repo", owner: o,
              features: {
                code_scanning: { status: :enrolled, count: 1 },
                dependabot_alerts: { status: :enrolled, count: 0 },
                secret_scanning: { status: :enrolled, count: 0 },
              })
          end

          enterprise_security_manager_team = create :enterprise_security_manager_team, business: @mt_biz
          @enterprise_security_manager = create :emu
          @mt_org.add_member @enterprise_security_manager # Because the factory doesn't set up the org teams sync
          enterprise_security_manager_team.bulk_add_members(users: [@enterprise_security_manager])
        end
      end

      setup do
        @parser = CoverageQueryParser.new("")
        Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

        SecurityCenter::SecurityFeatures.stubs(
          code_scanning_enabled_for_instance?: true,
          secret_scanning_enabled_for_instance?: true,
          dependabot_alerts_enabled_for_instance?: true,
        )

        CodeScanning::AutoCodeql.any_instance.stubs(:can_enable?).returns(true)
        CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(true)
        CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)

        SecurityCenter::Filters::ByCustomProperty.any_instance.stubs(:es_repo_ids).returns(@org1.repositories.pluck(:id))

        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
      end

      # Returns an array of 2-tuples of the form [[pos_filter, neg_filter], expected_query_count]
      def self.basic_filters_and_sort_with_query_counts
        # Author these to always match at least one repo so we can evaluate how many queries are made.
        [
          [["repo", "NOT mixed"], 10],
          [["archived:false", "-archived:true"], 10],
          [["code-scanning-alerts:enabled", "-code-scanning-alerts:disabled"], 10],
          [["code-scanning-pull-request-alerts:enabled", "-code-scanning-pull-request-alerts:disabled"], 10],
          [["code-scanning-default-setup:eligible", "-code-scanning-auto-codeql:not-eligible"], 1],
          [["dependabot-alerts:enabled", "-dependabot-alerts:disabled"], 10],
          [["dependabot-security-updates:enabled", "-dependabot-security-updates:disabled"], 10],
          [["advanced-security:enabled", "-advanced-security:disabled"], 10],
          [["is:private", "-is:public"], 10],
          [["owner:test-org-1", "-owner:whatever2"], 10],
          [["owner-type:organization", "-owner-type:user"], 10],
          [["repo:test-org-1-mixed-repo", "-repo:whatever"], 10],
          [["secret-scanning-alerts:enabled", "-secret-scanning-alerts:disabled"], 10],
          [["secret-scanning-push-protection:enabled", "-secret-scanning-push-protection:disabled"], 10],
          [["sort:repos", "sort:last-updated"], 10],
          [["team:test-org-1-mixed-repo-team", "-team:test-org-1-mixed-repo-team"], 14],
          [["topic:apples", "-topic:oranges"], 12],
          [["props.custom:property", "-props.custom:property"], 10],
        ]
      end

      context "#run" do
        basic_filters_and_sort_with_query_counts.each do |filters, query_count|
          filters.each do |filter|
            test "basic test exercising filter: #{filter.start_with?("-") ? filter.sub("-", "negated ") : filter}" do
              @parser = CoverageQueryParser.new(filter)
              assert_nothing_raised do
                assert_queries(count: query_count) do
                  ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 25).run
                end
              end
            end
          end
        end

        test "basic test exercising all filters at once" do
          all_filters = self.class.basic_filters_and_sort_with_query_counts.map(&:first).flatten.join(" ")
          @parser = CoverageQueryParser.new(all_filters)

          # Make sure we're using all qualifiers, plus unqualified text
          assert_equal CoverageQueryParser::QUALIFIERS.size + 1, self.class.basic_filters_and_sort_with_query_counts.size

          assert_nothing_raised do
            assert_queries(count: 13) do
              ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 25).run
            end
          end
        end

        test "returns results only for the provided organization" do
          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 25).run
          end.tap do |result|
            list_items = result.list_items

            assert_equal @org1.repositories.size, list_items.size
            assert_same_elements \
              @org1.repositories.map(&:name),
              list_items.map { |r| r.repo_metadata.name }
          end

          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org2, parser: @parser, page_size: 25).run
          end.tap do |result|
            list_items = result.list_items

            assert_equal @org2.repositories.size, list_items.size
            assert_same_elements \
              @org2.repositories.map(&:name),
              list_items.map { |r| r.repo_metadata.name }
          end
        end

        context "for businesses with enterprise managed users on Dotcom", skip_enterprise: true do
          context "includes EMU-owned repos" do
            test "as business owner with own repos" do
              assert_queries(count: 18) do
                assert_queries_matching SELECT_REPOSITORY_UNLOCKS_REGEX, 1 do
                  ListDataQuery.for_organizations(user: @mt_biz_owner, business: @mt_biz, organizations: [@mt_org], parser: CoverageQueryParser.new(""), page_size: 25).run
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
              assert_queries(count: 18) do
                assert_queries_matching SELECT_REPOSITORY_UNLOCKS_REGEX, 1 do
                  ListDataQuery.for_organizations(user: @mt_biz_owner, business: @mt_biz, organizations: [@mt_org], parser: CoverageQueryParser.new(""), page_size: 25).run
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

            test "as enterprise security manager with repos owned by another user" do
              assert_queries(count: 18) do
                assert_queries_matching SELECT_REPOSITORY_UNLOCKS_REGEX, 1 do
                  ListDataQuery.for_organizations(user: @enterprise_security_manager, business: @mt_biz, organizations: [@mt_org], parser: CoverageQueryParser.new(""), page_size: 25).run
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

            assert_queries(count: 13) do
              ListDataQuery.for_organizations(user: @mt_user, business: @mt_biz, organizations: [@mt_org], parser: CoverageQueryParser.new(""), page_size: 25).run
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
            assert_queries(count: 13) do
              ListDataQuery.for_organizations(user: @owner, business: @business, organizations: [@org1, @org2], parser: CoverageQueryParser.new(""), page_size: 25).run
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

              assert_queries(count: 18) do
                assert_queries_matching SELECT_REPOSITORY_UNLOCKS_REGEX, 0 do
                  ListDataQuery.for_organizations(user: @owner, business: @business, organizations: [@org1, @org2], parser: CoverageQueryParser.new(""), page_size: 25).run
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

              assert_queries(count: 19) do
                assert_queries_matching SELECT_REPOSITORY_UNLOCKS_REGEX, 1 do
                  ListDataQuery.for_organizations(user: other_biz_owner, business: @business, organizations: [@org1, @org2], parser: CoverageQueryParser.new(""), page_size: 25).run
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

            assert_queries(count: 13) do
              ListDataQuery.for_organizations(user: @owner, business: @business, organizations: [@org1, @org2], parser: CoverageQueryParser.new(""), page_size: 25).run
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

            assert_queries(count: 13) do
              ListDataQuery.for_organizations(user: @owner, business: @business, organizations: [@org1, @org2], parser: CoverageQueryParser.new(""), page_size: 25).run
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

        test "returns results limited by provided repository ids" do
          # no filter
          expected = [@cs_repo, @dbot_repo, @ss_repo, @mixed_repo]
          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, repo_ids: nil, parser: @parser, page_size: 25).run
          end.tap do |result|
            list_items = result.list_items

            assert_equal expected.size, list_items.size
            assert_same_elements \
              expected.map(&:name),
              list_items.map { |r| r.repo_metadata.name }
          end

          # partial filter
          expected = [@cs_repo, @dbot_repo, @ss_repo]
          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, repo_ids: expected.map(&:id), parser: @parser, page_size: 25).run
          end.tap do |result|
            list_items = result.list_items

            assert_equal expected.size, list_items.size
            assert_same_elements \
              expected.map(&:name),
              list_items.map { |r| r.repo_metadata.name }
          end

          # all filter
          expected = []
          assert_queries(count: 0) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, repo_ids: expected.map(&:id), parser: @parser, page_size: 25).run
          end.tap do |result|
            assert_empty result.list_items
          end
        end

        test "limits results returned by page_size" do
          @parser = CoverageQueryParser.new("sort:repos")
          repo_count = @org1.repositories.size

          # page_size less than total results
          # 'will_paginate' adds an extra query to get the count for 'total_entries' since the result count equals the page size
          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 2).run
          end.tap do |result|
            list_items = result.list_items

            assert_equal 2, list_items.size
            assert_equal @org1.repositories.map(&:name).sort.first(2), list_items.map { |r| r.repo_metadata.name }
          end

          # page_size equal to total results
          # 'will_paginate' adds an extra query to get the count for 'total_entries' since the result count equals the page size
          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: repo_count).run
          end.tap do |result|
            list_items = result.list_items

            assert_equal repo_count, list_items.size
            assert_equal @org1.repositories.map(&:name).sort, list_items.map { |r| r.repo_metadata.name }
          end

          # page_size greater than total results
          # 'will_paginate' knows it doesn't need an extra query to get the count for 'total_entries' since there are fewer results than the page size
          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: repo_count + 1).run
          end.tap do |result|
            list_items = result.list_items

            assert_equal repo_count, list_items.size
            assert_equal repo_count, list_items.total_entries
            assert_equal 1, list_items.total_pages
            assert_equal @org1.repositories.map(&:name).sort, list_items.map { |r| r.repo_metadata.name }
          end
        end

        test "returns results for the requested page of data" do
          @parser = CoverageQueryParser.new("sort:repos")

          org = @org1
          page_size = 3
          expected_total_pages = (org.repositories.size.to_f / page_size).ceil

          # 'will_paginate' adds an extra query to get the count for 'total_entries' since the result count equals the page size
          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: org, parser: @parser, page_size: page_size).run(page: 1)
          end.tap do |result|
            list_items = result.list_items

            assert_equal page_size, list_items.size
            page_size.times do |i|
              assert_equal org.repositories.map(&:name).sort[i], list_items[i].repo_metadata.name
            end
          end

          # Whether 'will_paginate' adds an extra query to get the count for 'total_entries' depends on if the number of results equals the page size
          expected_results_count = (org.repositories.size % page_size).then { |n| n.zero? ? page_size : n }
          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: org, parser: @parser, page_size: page_size).run(page: expected_total_pages)
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
          # Queries: 1: count by archived, 2: current page
          assert_queries(count: 1) do
            ListDataQuery.for_organization(user: @owner, organization: org, parser: @parser, page_size: page_size).run(page: expected_total_pages + 1)
          end.tap do |result|
            list_items = result.list_items

            assert_equal 0, list_items.size
          end
        end

        test "returns expected metadata for each repo" do
          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 25).run
          end.tap do |result|
            list_items = result.list_items

            assert_equal list_items.map(&:repo_metadata).map(&:name).uniq.size, list_items.size
            assert_equal @org1.repositories.size, list_items.size
            list_items.each do |r|
              @org1.repositories.find_by!(name: r.repo_metadata.name).tap do |repo|
                assert_equal urls.repository_security_overview_path(repo.owner, repo), r.repo_metadata.href
                assert_equal repo.visibility, r.repo_metadata.visibility
                assert_equal repo.pushed_at, r.repo_metadata.updated_at
              end
            end
          end
        end

        test "uses repo's root URL for temporary private forks" do
          owner = create(:user)
          org = create(:organization, admin: owner)

          GitHub.context.push(actor_id: owner.id) # Avoids `ActiveRecord::RecordInvalid: Validation failed: Updater must exist`
          advisory_repo = create_repo("#{org}-advisory-repo", owner: org, features: { secret_scanning: { status: :enrolled, count: 0 } })
          workspace_repo = create_workspace_repo(advisory_repo, actor: owner)

          assert_queries(count: 9) do
            ListDataQuery.for_organization(user: owner, organization: org, parser: @parser, page_size: 25).run
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

        test "returns expected coverages for each repo" do
          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 25).run
          end.tap do |result|
            list_items = result.list_items

            assert_equal @org1.repositories.size, list_items.size
            assert list_items.map(&:repo_metadata).map(&:name).uniq.size == list_items.size

            list_items.each do |r|
              assert_equal ["Dependabot", "Code scanning", "Secret scanning"], r.repo_coverages_list.map(&:feature)

              case r.repo_metadata.name
              when @cs_repo.name
                r.repo_coverages_list[0].tap do |c|
                  assert_empty c.coverages
                  assert_equal "Not enabled", c.no_coverages_reason
                end

                r.repo_coverages_list[1].tap do |c|
                  assert_equal ["Alerts", "Pull request alerts"], c.coverages
                  assert_equal "Needs setup", c.no_coverages_reason
                end

                r.repo_coverages_list[2].tap do |c|
                  assert_empty c.coverages
                  assert_equal "Not enabled", c.no_coverages_reason
                end
              when @dbot_repo.name
                r.repo_coverages_list[0].tap do |c|
                  assert_equal ["Alerts", "Security updates"], c.coverages
                  assert_equal "Not enabled", c.no_coverages_reason
                end

                r.repo_coverages_list[1].tap do |c|
                  assert_empty c.coverages
                  assert_equal "Needs setup", c.no_coverages_reason
                end

                r.repo_coverages_list[2].tap do |c|
                  assert_empty c.coverages
                  assert_equal "Not enabled", c.no_coverages_reason
                end
              when @ss_repo.name
                r.repo_coverages_list[0].tap do |c|
                  assert_empty c.coverages
                  assert_equal "Not enabled", c.no_coverages_reason
                end

                r.repo_coverages_list[1].tap do |c|
                  assert_empty c.coverages
                  assert_equal "Needs setup", c.no_coverages_reason
                end

                r.repo_coverages_list[2].tap do |c|
                  assert_equal ["Alerts", "Push protection"], c.coverages
                  assert_equal "Not enabled", c.no_coverages_reason
                end
              when @mixed_repo.name
                r.repo_coverages_list[0].tap do |c|
                  assert_equal ["Alerts"], c.coverages
                  assert_equal "Not enabled", c.no_coverages_reason
                end

                r.repo_coverages_list[1].tap do |c|
                  assert_equal ["Alerts"], c.coverages
                  assert_equal "Needs setup", c.no_coverages_reason
                end

                r.repo_coverages_list[2].tap do |c|
                  assert_equal ["Alerts"], c.coverages
                  assert_equal "Not enabled", c.no_coverages_reason
                end
              else
                raise "Unexpected repo #{r.repo_metadata.name}"
              end
            end
          end
        end

        test "only returns coverages for security features enabled at the instance level" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 25).run
          end.tap do |result|
            result.list_items.each do |r|
              assert_equal ["Dependabot", "Code scanning", "Secret scanning"], r.repo_coverages_list.map(&:feature)
            end
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: false,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 25).run
          end.tap do |result|
            result.list_items.each do |r|
              assert_equal ["Dependabot", "Secret scanning"], r.repo_coverages_list.map(&:feature)
            end
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: false,
            dependabot_alerts_enabled_for_instance?: true,
          )

          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 25).run
          end.tap do |result|
            result.list_items.each do |r|
              assert_equal ["Dependabot", "Code scanning"], r.repo_coverages_list.map(&:feature)
            end
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: false,
          )

          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 25).run
          end.tap do |result|
            result.list_items.each do |r|
              assert_equal ["Code scanning", "Secret scanning"], r.repo_coverages_list.map(&:feature)
            end
          end

          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: false,
            secret_scanning_enabled_for_instance?: false,
            dependabot_alerts_enabled_for_instance?: false,
          )

          assert_queries(count: 0) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 25).run
          end.tap do |result|
            result.list_items.each do |r|
              assert_empty [], r.repo_coverages_list
            end
          end
        end

        test "includes the expected feature_statuses for each repo" do
          T.must(RepositorySecurityCenterStatus.where(repository_id: @cs_repo.id, feature_type: "code_scanning_auto_codeql").take).update(scanning_status: :not_eligible)

          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 25).run
          end.tap do |result|
            list_items = result.list_items

            assert_equal @org1.repositories.size, list_items.size
            assert list_items.map(&:repo_metadata).map(&:name).uniq.size == list_items.size

            list_items.each do |r|
              assert_equal ["Dependabot", "Code scanning", "Secret scanning"], r.repo_coverages_list.map(&:feature)

              case r.repo_metadata.name
              when @cs_repo.name
                r.repo_coverages_list[0].tap do |c|
                  feature_statuses = {
                    dependabot_alerts: "not_enrolled",
                    dependabot_security_updates: "not_enrolled",
                    dependabot_version_updates: "not_enrolled"
                  }
                  assert_equal feature_statuses,  c.feature_statuses
                end

                r.repo_coverages_list[1].tap do |c|
                  feature_statuses = {
                    code_scanning: "enrolled",
                    code_scanning_pr_reviews: "enrolled",
                    code_scanning_auto_codeql: "not_eligible"
                  }
                  assert_equal feature_statuses,  c.feature_statuses
                end

                r.repo_coverages_list[2].tap do |c|
                  feature_statuses = {
                    secret_scanning: "not_enrolled",
                    secret_scanning_push_protection: "not_enrolled",
                  }
                  assert_equal feature_statuses,  c.feature_statuses
                end
              when @dbot_repo.name
                r.repo_coverages_list[0].tap do |c|
                  feature_statuses = {
                    dependabot_alerts: "enrolled",
                    dependabot_security_updates: "enrolled",
                    dependabot_version_updates: "not_enrolled"
                  }
                  assert_equal feature_statuses,  c.feature_statuses
                end

                r.repo_coverages_list[1].tap do |c|
                  feature_statuses = {
                    code_scanning: "not_enrolled",
                    code_scanning_pr_reviews: "not_enrolled",
                    code_scanning_auto_codeql: "not_enrolled"
                  }
                  assert_equal feature_statuses,  c.feature_statuses
                end

                r.repo_coverages_list[2].tap do |c|
                  feature_statuses = {
                    secret_scanning: "not_enrolled",
                    secret_scanning_push_protection: "not_enrolled",
                  }
                  assert_equal feature_statuses,  c.feature_statuses
                end
              when @ss_repo.name
                r.repo_coverages_list[0].tap do |c|
                  feature_statuses = {
                    dependabot_alerts: "not_enrolled",
                    dependabot_security_updates: "not_enrolled",
                    dependabot_version_updates: "not_enrolled"
                  }
                  assert_equal feature_statuses,  c.feature_statuses
                end

                r.repo_coverages_list[1].tap do |c|
                  feature_statuses = {
                    code_scanning: "not_enrolled",
                    code_scanning_pr_reviews: "not_enrolled",
                    code_scanning_auto_codeql: "not_enrolled"
                  }
                  assert_equal feature_statuses,  c.feature_statuses
                end

                r.repo_coverages_list[2].tap do |c|
                  feature_statuses = {
                    secret_scanning: "enrolled",
                    secret_scanning_push_protection: "enrolled",
                  }
                  assert_equal feature_statuses,  c.feature_statuses
                end
              when @mixed_repo.name
                r.repo_coverages_list[0].tap do |c|
                  feature_statuses = {
                    dependabot_alerts: "enrolled",
                    dependabot_security_updates: "not_enrolled",
                    dependabot_version_updates: "not_enrolled"
                  }
                  assert_equal feature_statuses,  c.feature_statuses
                end

                r.repo_coverages_list[1].tap do |c|
                  feature_statuses = {
                    code_scanning: "enrolled",
                    code_scanning_pr_reviews: "not_enrolled",
                    code_scanning_auto_codeql: "not_enrolled"
                  }
                  assert_equal feature_statuses,  c.feature_statuses
                end

                r.repo_coverages_list[2].tap do |c|
                  feature_statuses = {
                    secret_scanning: "enrolled",
                    secret_scanning_push_protection: "not_enrolled",
                  }
                  assert_equal feature_statuses,  c.feature_statuses
                end
              else
                raise "Unexpected repo #{r.repo_metadata.name}"
              end
            end
          end
        end

        test "it includes default setup if enabled" do
          CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)

          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org3, parser: @parser, page_size: 25).run
          end.tap do |result|
            assert_equal 2, result.list_items.count
            result.list_items[1].tap do |r|
              r.repo_coverages_list[1].tap do |c|
                assert_equal ["Alerts", "Default setup"], c.coverages
                assert_equal "Needs setup", c.no_coverages_reason
              end
            end
          end
        end

        test "it does not says 'Updating...' if code scanning default setup is enabling but async feature flag is enabled" do
          CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(true)

          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org3, parser: @parser, page_size: 25).run
          end.tap do |result|
            result.list_items[0].tap do |r|
              r.repo_coverages_list[1].tap do |c|
                assert_equal ["Alerts"], c.coverages
                assert_equal "Needs setup", c.no_coverages_reason
              end
            end
          end
        end

        context "secret scanning alerts coverage name" do
          test "returns 'Alerts to partners' for public repos if public repo secret scanning is unavailable", skip_enterprise: true do
            SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(false)

            org = create(:organization, admin: @owner)
            public_repo_with_secret_scanning = create_repo("#{org}-ss-public-repo-with-secret-scanning", visibility: :public, owner: org, features: { secret_scanning: { status: :enrolled, count: 0 } })
            public_repo_without_secret_scanning = create_repo("#{org}-ss-public-repo-without-secret-scanning", visibility: :public, owner: org)
            private_repo_with_secret_scanning = create_repo("#{org}-ss-private-repo-with-secret-scanning", visibility: :private, owner: org, features: { secret_scanning: { status: :enrolled, count: 0 } })
            private_repo_without_secret_scanning = create_repo("#{org}-ss-private-repo-without-secret-scanning", visibility: :private, owner: org)

            assert_queries(count: 9) do
              ListDataQuery.for_organization(user: @owner, organization: org, parser: @parser, page_size: 25).run
            end.tap do |result|
              list_items = result.list_items

              assert_equal org.repositories.size, list_items.size
              assert_same_elements org.repositories.map(&:name), list_items.map(&:repo_metadata).map(&:name)

              list_items.each do |r|
                repo_name = r.repo_metadata.name
                expected =
                  case repo_name
                  when public_repo_with_secret_scanning.name, public_repo_without_secret_scanning.name
                    "Alerts to partners"
                  when private_repo_with_secret_scanning.name
                    "Alerts"
                  when private_repo_without_secret_scanning.name
                    nil
                  else raise "Unexpected repo #{repo_name}"
                  end

                actual = r.repo_coverages_list.find { |c| c.feature == "Secret scanning" }.coverages[0]
                assert_nil actual, "Repo: #{repo_name}" if expected.nil?
                assert_equal expected, actual, "Repo: #{repo_name}" unless expected.nil?
              end
            end
          end

          test "returns 'Alerts to partners' for public repos without secret scanning if public repo secret scanning is available", skip_enterprise: true do
            SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(true)

            org = create(:organization, admin: @owner)
            public_repo_with_secret_scanning = create_repo("#{org}-ss-public-repo-with-secret-scanning", visibility: :public, owner: org, features: { secret_scanning: { status: :enrolled, count: 0 } })
            public_repo_without_secret_scanning = create_repo("#{org}-ss-public-repo-without-secret-scanning", visibility: :public, owner: org)
            private_repo_with_secret_scanning = create_repo("#{org}-ss-private-repo-with-secret-scanning", visibility: :private, owner: org, features: { secret_scanning: { status: :enrolled, count: 0 } })
            private_repo_without_secret_scanning = create_repo("#{org}-ss-private-repo-without-secret-scanning", visibility: :private, owner: org)

            assert_queries(count: 9) do
              ListDataQuery.for_organization(user: @owner, organization: org, parser: @parser, page_size: 25).run
            end.tap do |result|
              list_items = result.list_items

              assert_equal org.repositories.size, list_items.size
              assert_same_elements org.repositories.map(&:name), list_items.map(&:repo_metadata).map(&:name)

              list_items.each do |r|
                repo_name = r.repo_metadata.name
                expected =
                  case repo_name
                  when public_repo_without_secret_scanning.name
                    "Alerts to partners"
                  when public_repo_with_secret_scanning.name, private_repo_with_secret_scanning.name
                    "Alerts"
                  when private_repo_without_secret_scanning.name
                    nil
                  else raise "Unexpected repo #{repo_name}"
                  end

                actual = r.repo_coverages_list.find { |c| c.feature == "Secret scanning" }.coverages[0]
                assert_nil actual, "Repo: #{repo_name}" if expected.nil?
                assert_equal expected, actual, "Repo: #{repo_name}" unless expected.nil?
              end
            end
          end

          test "returns 'Alerts' for all repo visibilities", enterprise_only: true do
            org = create(:organization, admin: @owner)
            public_repo_with_secret_scanning = create_repo("#{org}-ss-public-repo-with-secret-scanning", visibility: :public, owner: org, features: { secret_scanning: { status: :enrolled, count: 0 } })
            public_repo_without_secret_scanning = create_repo("#{org}-ss-public-repo-without-secret-scanning", visibility: :public, owner: org)
            private_repo_with_secret_scanning = create_repo("#{org}-ss-private-repo-with-secret-scanning", visibility: :private, owner: org, features: { secret_scanning: { status: :enrolled, count: 0 } })
            private_repo_without_secret_scanning = create_repo("#{org}-ss-private-repo-without-secret-scanning", visibility: :private, owner: org)

            assert_queries(count: 9) do
              ListDataQuery.for_organization(user: @owner, organization: org, parser: @parser, page_size: 25).run
            end.tap do |result|
              list_items = result.list_items

              assert_equal org.repositories.size, list_items.size
              assert_same_elements org.repositories.map(&:name), list_items.map(&:repo_metadata).map(&:name)

              list_items.each do |r|
                repo_name = r.repo_metadata.name
                expected =
                  case repo_name
                  when public_repo_with_secret_scanning.name, private_repo_with_secret_scanning.name
                    "Alerts"
                  when public_repo_without_secret_scanning.name, private_repo_without_secret_scanning.name
                    nil
                  else raise "Unexpected repo #{repo_name}"
                  end

                actual = r.repo_coverages_list.find { |c| c.feature == "Secret scanning" }.coverages[0]
                assert_nil actual, "Repo: #{repo_name}" if expected.nil?
                assert_equal expected, actual, "Repo: #{repo_name}" unless expected.nil?
              end
            end
          end
        end

        test "emits access_violation metrics if out-of-scope repos are returned by the query" do
          # make the root query ignore its org_id filter
          RepositorySecurityCenterConfig.stubs(:where).returns(RepositorySecurityCenterConfig.all)

          assert_queries(count: 10) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 25).run
          end
          assert_dogstats_increment("security_center.access_violation", tags: ["feature:coverage", "scope:organization"])
        end
      end

      context "#counts" do
        test "result contains active and archived counts" do
          assert_queries(count: 1) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 25).counts
          end.tap do |result|
            assert_equal @org1.repositories.size, result.active_count
            assert_equal 0, result.archived_count
          end
        end

        test "limits results returned by page_size" do
          @parser = CoverageQueryParser.new("sort:repos")
          repo_count = @org1.repositories.size

          # page_size less than total results
          # 'will_paginate' adds an extra query to get the count for 'total_entries' since the result count equals the page size
          assert_queries(count: 1) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 2).counts
          end.tap do |result|
            assert_equal (repo_count.to_f / 2).ceil, result.total_pages
          end

          # page_size equal to total results
          # 'will_paginate' adds an extra query to get the count for 'total_entries' since the result count equals the page size
          assert_queries(count: 1) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: repo_count).counts
          end.tap do |result|
            assert_equal 1, result.total_pages
          end

          # page_size greater than total results
          # 'will_paginate' knows it doesn't need an extra query to get the count for 'total_entries' since there are fewer results than the page size
          assert_queries(count: 1) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: repo_count + 1).counts
          end.tap do |result|
            assert_equal 1, result.total_pages
          end
        end

        test "returns expected counts for active and archived" do
          @ss_repo.security_center_config.update!(archived: true)

          assert_queries(count: 1) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 25).counts
          end.tap do |result|
            assert_equal 3, result.active_count
            assert_equal 1, result.archived_count
          end

          assert_queries(count: 1) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: CoverageQueryParser.new("secret-scanning-alerts:enabled"), page_size: 25).counts
          end.tap do |result|
            assert_equal 1, result.active_count
            assert_equal 1, result.archived_count
          end
        end
      end

      context "#all" do
        test "returns filtered repo relation for org" do
          # returns unexecuted relation
          rel = assert_queries(count: 0) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser, page_size: 0).all
          end

          assert_queries(count: 1) do
            rel.to_a
          end.tap do |result|
            assert_equal @org1.repositories.active.not_archived_scope.length, result.length
          end
        end
      end

      context "telemetry" do
        test "includes each applied filter as tags" do
          query = "archived:false is:private repo:repo-name secret-scanning:>0"
          ListDataQuery.for_organization(user: @owner, organization: @org1, parser: CoverageQueryParser.new(query), page_size: 25).run

          assert_dogstats_distribution("security_center.coverage_list_data_query.run.dist", tags: [
            "has_filter:by_archived",
            "has_filter:by_visibility",
            "has_filter:by_repository",
          ])
        end

        test "includes sort as tag" do
          query = "sort:repos"
          ListDataQuery.for_organization(user: @owner, organization: @org1, parser: CoverageQueryParser.new(query), page_size: 25).run

          assert_dogstats_distribution("security_center.coverage_list_data_query.run.dist", tags: ["sort_by:repos"])
        end

        test "ignores invalid sort in tags" do
          query = "sort:invalid"
          ListDataQuery.for_organization(user: @owner, organization: @org1, parser: CoverageQueryParser.new(query), page_size: 25).run

          assert_dogstats_distribution("security_center.coverage_list_data_query.run.dist", tags: ["sort_by:last-updated"])
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
          assert_duplicate_query_detection(ListDataQuery, 0) do
            result = yield
          end
        end

        result
      end

      def create_repo(name, owner:, visibility: :private, archived: false, features: {}, create_statuses_for_unspecified_features: true)
        factory = if visibility == :private
          :private_repository
        elsif visibility == :public
          :repository
        elsif visibility == :internal
          :internal_repository
        end

        create(factory, name: name, owner: owner).tap do |r|
          r.set_archived if archived

          create_config(r)

          all_feature_types = RepositorySecurityCenterStatus.primary_feature_types.flat_map do |primary_type|
            [primary_type] + RepositorySecurityCenterStatus.subfeatures_for(primary_type)
          end

          features.each do |feature, opts|
            opts => { status:, count: }
            raise "Unknown feature type #{feature}" unless all_feature_types.include?(feature)
            create_status(r, feature: feature, status: status, alert_count: count)
          end

          if create_statuses_for_unspecified_features
            (all_feature_types - features.keys).each do |feature|
              create_status(r, feature: feature, status: :not_enrolled)
            end
          end
        end
      end

      def create_workspace_repo(source_repo, actor:)
        GitHub.context.push(actor_id: actor.id) # Avoids `ActiveRecord::RecordInvalid: Validation failed: Updater must exist`
        advisory = create(:repository_advisory, repository: source_repo, author: actor)
        workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, actor).tap do |r|
          r.save!

          create_config(r)

          all_feature_types = RepositorySecurityCenterStatus.primary_feature_types.flat_map do |primary_type|
            [primary_type] + RepositorySecurityCenterStatus.subfeatures_for(primary_type)
          end

          all_feature_types.each do |feature|
            create_status(r, feature: feature, status: :not_enrolled)
          end
        end
      end

      def create_config(repo)
        create(
          :repository_security_center_config,
          repository: repo,
          ghas_enabled: true,
        )
      end

      def create_status(repo, feature:, status:, alert_count: 0)
        create(
          :repository_security_center_status,
          feature,
          scanning_status: status,
          scanning_count: alert_count,
          repository: repo,
        )
      end
    end
  end
end
