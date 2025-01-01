# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Risk
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

            result = risk_export_data_query(scope: org).query_data.first

            assert_equal "#{org.display_login}/#{repo.name}", result&.name_with_display_owner
            assert_equal repo.archived?, result&.archived
            assert_equal "2023-08-08 14:13:10 UTC", result&.updated_at
            assert_equal repo.visibility, result&.visibility
            assert_equal 1, result&.dependabot_alerts_count
            assert_equal 2, result&.code_scanning_alerts_count
            assert_equal 3, result&.secret_scanning_alerts_count
            assert_same_elements [topic1.name, topic2.name], result&.topics
            assert_same_elements [admin_team.slug, write_team.slug], result&.teams
          end
        end
      end

      test "allowed_repository_ids_by_feature filters repositories" do
        results = risk_export_data_query.query_data
        assert_equal @org1.repositories.size, results.size

        ids_by_feature = {
          dependabot_alerts: [@cs_repo.id, @dbot_repo.id, @no_alerts_repo.id],
          code_scanning: [@cs_repo.id],
          secret_scanning: [@ss_repo.id, @cs_repo.id],
        }

        results = risk_export_data_query(allowed_repository_ids_by_feature: ids_by_feature).query_data
        assert_equal 4, results.size
      end

      test "allowed_repository_ids_by_feature filters repository alert counts" do
        org = create(:organization, name: "org-name", admin: @owner)
        repo = create_repo("#{org.display_login}-repo-name", owner: org, dbot_count: 1, cs_count: 2, ss_count: 3)

        ids_by_feature = {
          dependabot_alerts: [repo.id],
          code_scanning: [],
          secret_scanning: [repo.id],
        }

        result = risk_export_data_query(scope: org, allowed_repository_ids_by_feature: ids_by_feature).query_data.first
        assert_equal 1, result&.dependabot_alerts_count
        assert_nil result&.code_scanning_alerts_count
        assert_equal 3, result&.secret_scanning_alerts_count
      end

      test "sorts by repo if no sort provided" do
        org = create(:organization, name: "org-name", admin: @owner)
        repo = create_repo("#{org.display_login}-repo-name", owner: org, dbot_count: 1, cs_count: 2, ss_count: 3)

        SecurityCenter::Risk::SortBy.any_instance.expects(:sort_option_or_default).with("repos").once.returns(:repos)

        risk_export_data_query(scope: org).query_data
      end

      test "overrides user's sort to sort by repo" do
        org = create(:organization, name: "org-name", admin: @owner)
        repo = create_repo("#{org.display_login}-repo-name", owner: org, dbot_count: 1, cs_count: 2, ss_count: 3)

        SecurityCenter::Risk::SortBy.any_instance.expects(:sort_option_or_default).with("dependabot").never
        SecurityCenter::Risk::SortBy.any_instance.expects(:sort_option_or_default).with("repos").once.returns(:repos)

        risk_export_data_query(scope: org, query_string: "sort:dependabot").query_data
      end

      private

      sig do
        params(
          scope: T.any(Organization, Business),
          user: User,
          query_string: String,
          allowed_repository_ids_by_feature: T.nilable(T::Hash[Symbol, T::Array[Integer]]),
          authorized_orgs: T::Array[Organization]
        ).returns(ExportDataQuery)
      end
      def risk_export_data_query(scope: @org1, user: @owner, query_string: "", allowed_repository_ids_by_feature: nil, authorized_orgs: [scope])
        ExportDataQuery.new(
          user:,
          scope:,
          parser: ::Orgs::SecurityCenter::RiskController::RiskQueryParser.new(query_string),
          authorized_orgs:,
          allowed_repository_ids_by_feature:,
        )
      end

      sig { params(name: String, owner: Organization, dbot_count: Integer, cs_count: Integer, ss_count: Integer).returns(Repository) }
      def create_repo(name, owner:,  dbot_count: 0, cs_count: 0, ss_count: 0)
        create(:private_repository, name: name, owner: owner).tap do |r|
          create(:repository_security_center_config, repository: r)
          create_status(r, feature: :dependabot_alerts, count: dbot_count)
          create_status(r, feature: :code_scanning, count: cs_count)
          create_status(r, feature: :secret_scanning, count: ss_count)
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
    end
  end
end
