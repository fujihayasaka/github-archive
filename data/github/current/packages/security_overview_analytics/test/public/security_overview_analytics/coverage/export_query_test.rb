# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Coverage
    class ExportQueryTest < GitHub::TestCase

      fixtures do
        @owner = create(:user)
        @owner_session = create(:user_session, user: @owner)
        @org1 = create(:organization, name: "test-org-1", admin: @owner).tap do |o|
          @cs_repo = create_repo("#{o}-cs-repo", owner: o, dbot_count: 0, cs_count: 1, ss_count: 0)
          @dbot_repo = create_repo("#{o}-dbot-repo", owner: o, dbot_count: 1, cs_count: 0, ss_count: 0)
          @ss_repo = create_repo("#{o}-ss-repo", owner: o, dbot_count: 0, cs_count: 0, ss_count: 1)
          @mixed_repo = create_repo("#{o}-mixed-repo", owner: o, dbot_count: 1, cs_count: 1, ss_count: 1)
          @no_alerts_repo = create_repo("#{o}-no-alerts-repo", owner: o, dbot_count: 0, cs_count: 0, ss_count: 0)
        end

        create(:custom_property_definition, :true_false, source: @org1, property_name: "prop-boolean").tap do |definition|
          create(:custom_property_value, definition:, target: @cs_repo, value: "true")
          create(:custom_property_value, definition:, target: @dbot_repo, value: "true")
          create(:custom_property_value, definition:, target: @ss_repo, value: "true")
        end
        create(:custom_property_definition, :string, source: @org1, property_name: "prop-string").tap do |definition|
          create(:custom_property_value, definition:, target: @cs_repo, value: "my value")
        end
        create(:custom_property_definition, :single_select, source: @org1, property_name: "prop-single", allowed_values: %w[foo bar baz]).tap do |definition|
          create(:custom_property_value, definition:, target: @dbot_repo, value: "foo")
        end
        create(:custom_property_definition, :multi_select, source: @org1, property_name: "prop-multi", allowed_values: %w[one two three]).tap do |definition|
          create(:custom_property_value, definition:, target: @ss_repo, value: "one")
        end

        unless GitHub.enterprise?
          @mt_user = create(:emu)
          @mt_biz = @mt_user.enterprise_managed_business
          @mt_biz_owner = @mt_biz.owners.first
          @mt_biz.add_owner(@mt_user, actor: nil)

          @mt_user.tap do |o|
            @mt_user_ss_repo = create_repo("#{o}-mt-user-ss-repo", owner: @mt_user, dbot_count: 0, cs_count: 0, ss_count: 1)
          end

          @mt_org = create(:business_plus_organization, business: @mt_biz, admin: @mt_user, name: "test-org-mt")
        end
      end

      setup do
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
        SecurityCenter::SecurityFeatures.stubs(
          code_scanning_enabled_for_instance?: true,
          secret_scanning_enabled_for_instance?: true,
          dependabot_alerts_enabled_for_instance?: true,
        )
      end

      test "formats data correctly" do
        Time.use_zone("America/Denver") do
          Timecop.freeze(Time.utc(2023, 8, 8, 14, 13, 10)) do
            org = create(:organization, name: "org-name", admin: @owner)
            repo = create_repo("#{org.display_login}-repo-name", owner: org, dbot_count: 1, cs_count: 2, ss_count: 3)

            topic1 = create(:topic)
            create(:repository_topic, topic: topic1, repository: repo)
            topic2 = create(:topic)
            create(:repository_topic, topic: topic2, repository: repo)

            admin_team = create(:team, organization: org, name: "team,admin").tap do |team|
              team.add_repository(repo, :admin)
            end

            write_team = create(:team, organization: org, name: "team,write").tap do |team|
              team.add_repository(repo, :write)
            end

            read_team = create(:team, organization: org, name: "team,read").tap do |team|
              team.add_repository(repo, :read)
            end

            result = coverage_export_data_query(scope: org).perform.items.first

            assert_equal "#{org.display_login}/#{repo.name}", result&.name_with_display_owner
            assert_equal "ORGANIZATION", result&.owner_type
            assert_equal repo.archived?, result&.archived
            assert_equal "2023-08-08 14:13:10 UTC", result&.updated_at
            assert_equal repo.visibility, result&.visibility

            assert_equal "enabled", result&.advanced_security_status
            assert_equal "enabled", result&.dependabot_alerts_status
            assert_equal "enabled", result&.dependabot_security_updates_status
            assert_equal "enabled", result&.code_scanning_alerts_status
            assert_equal "enabled", result&.code_scanning_pull_request_alerts_status
            assert_equal "enabled", result&.code_scanning_default_setup
            assert_equal "enabled", result&.secret_scanning_alerts_status
            assert_equal "enabled", result&.secret_scanning_push_protection_status
            assert_same_elements [topic1.name, topic2.name], result&.topics
            assert_same_elements [admin_team.slug, write_team.slug], result&.teams
          end
        end
      end

      test "correctly sets owner_type to USER for a user-owned repo", skip_enterprise: true do
        ::SecurityCenter::FeatureFlagHelper.stubs(:allows_emu_owned_repositories?).returns(true)
        ::SecurityProduct::Permissions::BusinessAuthz.any_instance.stubs(:can_view_user_owned_repository_alerts?).returns(true)
        ::AdvancedSecurity::Features::Business::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)

        result = coverage_export_data_query(scope: @mt_biz, authorized_orgs: [@mt_org]).perform(page: 1).items.first

        assert_equal "#{@mt_user.display_login}/#{@mt_user_ss_repo.name}", result&.name_with_display_owner
        assert_equal "USER", result&.owner_type
      end

      test "allowed_repository_ids filters repositories" do
        results = coverage_export_data_query.perform.items
        assert_equal @org1.repositories.size, results.size

        repo_ids = [@cs_repo.id, @ss_repo.id]

        results = coverage_export_data_query(allowed_repository_ids: repo_ids).perform.items
        assert_equal 2, results.size
      end

      test "sorts by repo if no sort provided" do
        results = coverage_export_data_query(scope: @org1).perform.items
        assert_equal \
          @org1.repositories.order(name: :asc).map(&:name_with_display_owner),
          results.map(&:name_with_display_owner)
      end

      test "overrides user's sort to sort by repo" do
        results = coverage_export_data_query(scope: @org1, query_string: "sort:dependabot").perform.items
        assert_equal \
          @org1.repositories.order(name: :asc).map(&:name_with_display_owner),
          results.map(&:name_with_display_owner)
      end

      test "returns eligibility information for code scanning default setup" do
        org = create(:organization, name: "org-name", admin: @owner)
        create_repo("repo-eligible", owner: org,  dbot_count: 0, cs_count: 0, ss_count: 0, subfeature_statuses: { code_scanning_auto_codeql: :eligible })
        create_repo("repo-enrolled", owner: org,  dbot_count: 0, cs_count: 0, ss_count: 0, subfeature_statuses: { code_scanning_auto_codeql: :enrolled })
        create_repo("repo-not-eligible", owner: org,  dbot_count: 0, cs_count: 0, ss_count: 0, subfeature_statuses: { code_scanning_auto_codeql: :not_eligible })

        results = coverage_export_data_query(scope: org).perform.items

        assert_equal "not-enabled", results[0]&.code_scanning_default_setup
        assert_equal "enabled", results[1]&.code_scanning_default_setup
        assert_equal "ineligible", results[2]&.code_scanning_default_setup
      end

      context ".for_business", skip_enterprise: true do
        test "does not include repository properties" do
          results = coverage_export_data_query(scope: @mt_biz, authorized_orgs: [@mt_org]).perform(page: 1).items
          results.each do |item|
            assert_empty item.repository_properties
          end
        end
      end

      context ".for_organization" do
        test "include repository properties" do
          ::SecurityCenter::FeatureFlagHelper.stubs(:coverage_export_include_repo_properties?).returns(true)

          results = coverage_export_data_query.perform.items
          results.each do |item|
            assert_same_elements %w[prop-boolean prop-multi prop-single prop-string], item.repository_properties.keys
          end
        end

        test "does not include repository properties when ff disabled" do
          ::SecurityCenter::FeatureFlagHelper.stubs(:coverage_export_include_repo_properties?).returns(false)

          results = coverage_export_data_query.perform.items
          results.each do |item|
            assert_empty item.repository_properties
          end
        end
      end

      private

      sig do
        params(
          scope: T.any(Organization, Business),
          user: User,
          user_session: UserSession,
          query_string: String,
          allowed_repository_ids: T.nilable(T::Array[Integer]),
          authorized_orgs: T::Array[Organization]
        ).returns(ExportQuery)
      end
      def coverage_export_data_query(scope: @org1, user: @owner, user_session: @owner_session, query_string: "", allowed_repository_ids: nil, authorized_orgs: [scope])
        if scope.is_a? Business
          ExportQuery.for_business(
            business: scope,
            organizations: authorized_orgs,
            user:,
            parser: Search::Queries::SecurityCenter::CoverageQueryParser.new(query_string),
          )
        else
          ExportQuery.for_organization(
            organization: scope,
            user:,
            user_session:,
            parser: Search::Queries::SecurityCenter::CoverageQueryParser.new(query_string),
            repo_ids: allowed_repository_ids,
          )
        end
      end

      sig { params(name: String, owner: T.any(Organization, User), dbot_count: Integer, cs_count: Integer, ss_count: Integer, subfeature_statuses: T::Hash[Symbol, Symbol]).returns(::Repository) }
      def create_repo(name, owner:,  dbot_count: 0, cs_count: 0, ss_count: 0, subfeature_statuses: {})
        create(:private_repository, name: name, owner: owner).tap do |r|
          repository_metadata = create(:soa_repository, repository: r)
          create(
            :soa_feature_status,
            repository_metadata:,
            advanced_security_status: "ENABLED",
            dependabot_alerts_status: dbot_count > 0 ? "ENABLED" : "NOT_ENABLED",
            dependabot_alerts_total_count: dbot_count,
            code_scanning_alerts_status: cs_count > 0 ? "ENABLED" : "NOT_ENABLED",
            code_scanning_alerts_total_count: cs_count,
            secret_scanning_alerts_status: ss_count > 0 ? "ENABLED" : "NOT_ENABLED",
            secret_scanning_alerts_total_count: ss_count,
            dependabot_security_updates_status: (subfeature_statuses[:dependabot_security_updates] || :enrolled) == :enrolled ? "ENABLED" : "NOT_ENABLED",
            dependabot_version_updates_status: (subfeature_statuses[:dependabot_version_updates] || :enrolled) == :enrolled ? "ENABLED" : "NOT_ENABLED",
            code_scanning_pr_reviews_status: (subfeature_statuses[:code_scanning_pr_reviews] || :enrolled) == :enrolled ? "ENABLED" : "NOT_ENABLED",
            code_scanning_auto_codeql_status: \
              case subfeature_statuses[:code_scanning_auto_codeql]
              when nil; "ENABLED"
              when :enrolled; "ENABLED"
              when :eligible; "ELIGIBLE"
              else "NOT_ELIGIBLE"
              end,
            secret_scanning_push_protection_status: (subfeature_statuses[:secret_scanning_push_protection] || :enrolled) == :enrolled ? "ENABLED" : "NOT_ENABLED",
          )
        end
      end
    end
  end
end
