# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Coverage
    class ExportDataQueryTest < GitHub::TestCase
      extend T::Sig

      fixtures do
        @owner = create(:user)
        @org1 = create(:organization, name: "test-org-1", admin: @owner).tap do |o|
          @cs_repo = create_repo("#{o}-cs-repo", owner: o, dbot_count: 0, cs_count: 1, ss_count: 0)
          @dbot_repo = create_repo("#{o}-dbot-repo", owner: o, dbot_count: 1, cs_count: 0, ss_count: 0)
          @ss_repo = create_repo("#{o}-ss-repo", owner: o, dbot_count: 0, cs_count: 0, ss_count: 1)
          @mixed_repo = create_repo("#{o}-mixed-repo", owner: o, dbot_count: 1, cs_count: 1, ss_count: 1)
          @no_alerts_repo = create_repo("#{o}-no-alerts-repo", owner: o, dbot_count: 0, cs_count: 0, ss_count: 0)
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

            result = coverage_export_data_query(scope: org).query_data.first

            assert_equal "#{org.display_login}/#{repo.name}", result&.name_with_display_owner
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

      test "allowed_repository_ids filters repositories" do
        results = coverage_export_data_query.query_data
        assert_equal @org1.repositories.size, results.size

        repo_ids = [@cs_repo.id, @ss_repo.id]

        results = coverage_export_data_query(allowed_repository_ids: repo_ids).query_data
        assert_equal 2, results.size
      end

      test "sorts by repo if no sort provided" do
        org = create(:organization, name: "org-name", admin: @owner)
        repo = create_repo("#{org.display_login}-repo-name", owner: org, dbot_count: 1, cs_count: 2, ss_count: 3)

        SecurityCenter::Coverage::SortBy.any_instance.expects(:sort_option_or_default).with("repos").once.returns(:repos)

        coverage_export_data_query(scope: org).query_data
      end

      test "overrides user's sort to sort by repo" do
        org = create(:organization, name: "org-name", admin: @owner)
        repo = create_repo("#{org.display_login}-repo-name", owner: org, dbot_count: 1, cs_count: 2, ss_count: 3)

        SecurityCenter::Coverage::SortBy.any_instance.expects(:sort_option_or_default).with("dependabot").never
        SecurityCenter::Coverage::SortBy.any_instance.expects(:sort_option_or_default).with("repos").once.returns(:repos)

        coverage_export_data_query(scope: org, query_string: "sort:dependabot").query_data
      end

      test "returns eligibility information for code scanning default setup" do
        org = create(:organization, name: "org-name", admin: @owner)
        create_repo("repo-enrolled", owner: org,  dbot_count: 0, cs_count: 0, ss_count: 0, subfeature_statues: { code_scanning_auto_codeql: :enrolled })
        create_repo("repo-not-enrolled", owner: org,  dbot_count: 0, cs_count: 0, ss_count: 0, subfeature_statues: { code_scanning_auto_codeql: :not_enrolled })
        create_repo("repo-not-eligible", owner: org,  dbot_count: 0, cs_count: 0, ss_count: 0, subfeature_statues: { code_scanning_auto_codeql: :not_eligible })
        create_repo("repo-eligible", owner: org,  dbot_count: 0, cs_count: 0, ss_count: 0, subfeature_statues: { code_scanning_auto_codeql: :eligible })

        results = coverage_export_data_query(scope: org).query_data

        assert_equal "not-enabled", results[0]&.code_scanning_default_setup
        assert_equal "enabled", results[1]&.code_scanning_default_setup
        assert_equal "ineligible", results[2]&.code_scanning_default_setup
        assert_equal "not-enabled", results[3]&.code_scanning_default_setup
      end

      private

      sig do
        params(
          scope: T.any(Organization, Business),
          user: User,
          query_string: String,
          allowed_repository_ids: T.nilable(T::Array[Integer]),
          authorized_orgs: T::Array[Organization]
        ).returns(ExportDataQuery)
      end
      def coverage_export_data_query(scope: @org1, user: @owner, query_string: "", allowed_repository_ids: nil, authorized_orgs: [scope])
        ExportDataQuery.new(
          user:,
          scope:,
          parser: ::Orgs::SecurityCenter::CoverageController::CoverageQueryParser.new(query_string),
          authorized_orgs:,
          allowed_repository_ids:,
        )
      end

      sig { params(name: String, owner: Organization, dbot_count: Integer, cs_count: Integer, ss_count: Integer, subfeature_statues: T::Hash[Symbol, Symbol]).returns(Repository) }
      def create_repo(name, owner:,  dbot_count: 0, cs_count: 0, ss_count: 0, subfeature_statues: {})
        create(:private_repository, name: name, owner: owner).tap do |r|
          create(:repository_security_center_config, repository: r)
          create_status(r, feature: :dependabot_alerts, count: dbot_count)
          create_subfeature_status(r, feature: :dependabot_security_updates, status: subfeature_statues[:dependabot_security_updates])
          create_subfeature_status(r, feature: :dependabot_version_updates, status: subfeature_statues[:dependabot_version_updates])

          create_status(r, feature: :code_scanning, count: cs_count)
          create_subfeature_status(r, feature: :code_scanning_pr_reviews, status: subfeature_statues[:code_scanning_pr_reviews])
          create_subfeature_status(r, feature: :code_scanning_auto_codeql, status: subfeature_statues[:code_scanning_auto_codeql])

          create_status(r, feature: :secret_scanning, count: ss_count)
          create_subfeature_status(r, feature: :secret_scanning_push_protection, status: subfeature_statues[:secret_scanning_push_protection])
        end
      end

      sig { params(repo: Repository, feature: Symbol, count: Integer).returns(RepositorySecurityCenterStatus) }
      def create_status(repo, feature:, count:)
        create(
          :repository_security_center_status,
          feature,
          count > 0 ? :enrolled : :not_enrolled,
          scanning_count: count,
          repository: repo,
        )
      end

      sig { params(repo: Repository, feature: Symbol, status: T.nilable(Symbol)).returns(RepositorySecurityCenterStatus) }
      def create_subfeature_status(repo, feature:, status:)
        create(
          :repository_security_center_status,
          feature,
          status || :enrolled,
          scanning_count: 0,
          repository: repo,
        )
      end
    end
  end
end
