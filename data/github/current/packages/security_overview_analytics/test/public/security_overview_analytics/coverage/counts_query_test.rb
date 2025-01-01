# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Coverage
    class CountsQueryTest < GitHub::TestCase
      include GitHub::Memoizer
      include DogstatsTestHelpers
      include DuplicateQueryTestHelper

      CoverageQueryParser = ::Search::Queries::SecurityCenter::CoverageQueryParser

      fixtures do
        # Business
        GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
        @business = create(:global_business)

        @owner = create(:user).tap do |u|
          @owner_session = create(:user_session, user: u)

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
          @mixed_repo = create_repo("#{o}-mixed-repo", owner: o, archived: true,
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

        SecurityCenter::Filters::ByCustomProperty.any_instance.stubs(:es_repo_ids).returns(@org1.repositories.pluck(:id))

        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
      end

      context "#perform" do
        test "result contains active and archived counts" do
          assert_queries(count: GitHub.enterprise? ? 1 : 3) do
            CountsQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: @parser).perform(page_size: 25)
          end.tap do |result|
            assert_equal 3, result.active_count
            assert_equal 1, result.archived_count
          end
        end

        test "limits results returned by page_size" do
          @parser = CoverageQueryParser.new("sort:repos")
          repo_count = @org1.repositories.size

          # page_size less than total results
          # 'will_paginate' adds an extra query to get the count for 'total_entries' since the result count equals the page size
          assert_queries(count: GitHub.enterprise? ? 1 : 3) do
            CountsQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: @parser).perform(page_size: 2)
          end.tap do |result|
            assert_equal (repo_count.to_f / 2).ceil, result.total_pages
          end

          # page_size equal to total results
          # 'will_paginate' adds an extra query to get the count for 'total_entries' since the result count equals the page size
          assert_queries(count: 1) do
            CountsQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: @parser).perform(page_size: repo_count)
          end.tap do |result|
            assert_equal 1, result.total_pages
          end

          # page_size greater than total results
          # 'will_paginate' knows it doesn't need an extra query to get the count for 'total_entries' since there are fewer results than the page size
          assert_queries(count: 1) do
            CountsQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: @parser).perform(page_size: repo_count + 1)
          end.tap do |result|
            assert_equal 1, result.total_pages
          end
        end

        test "returns expected counts for active and archived" do
          ::SecurityOverviewAnalytics::Repository.find(@ss_repo.id).update!(archived: true)

          assert_queries(count: GitHub.enterprise? ? 1 : 3) do
            CountsQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: @parser).perform(page_size: 25)
          end.tap do |result|
            assert_equal 2, result.active_count
            assert_equal 2, result.archived_count
          end

          assert_queries(count: 1) do
            CountsQuery.for_organization(user: @owner, user_session: @owner_session, organization: @org1, parser: CoverageQueryParser.new("secret-scanning-alerts:enabled")).perform(page_size: 25)
          end.tap do |result|
            assert_equal 0, result.active_count
            assert_equal 2, result.archived_count
          end
        end
      end

      private

      def assert_queries(count: 0)
        result = T.let(nil, T.untyped)
        assert_query_count(count, ignore_feature_flags: true) do
          assert_duplicate_query_detection(CountsQuery, 0) do
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

          repository_metadata = create(:soa_repository, repository: r)

          create(
            :soa_feature_status,
            repository_metadata:,
            advanced_security_status: "NOT_ENABLED",
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
