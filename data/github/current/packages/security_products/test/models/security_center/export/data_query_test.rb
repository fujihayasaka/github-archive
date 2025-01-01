# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Export
    class DataQueryTest < GitHub::TestCase

      fixtures do
        @owner = create(:user)
        @org = create(:organization, name: "test-org-1", admin: @owner).tap do |o|
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

      test "filters results when passed a query string" do
        results = risk_export_data_query.run(list_data_query: create_list_data_query)
        assert_equal @org.repositories.size, results.size

        assert_equal 2, RepositorySecurityCenterStatus
          .where(repository_id: @org.repositories.pluck(:id), feature_type: "code_scanning")
          .where.not(scanning_count: 0)
          .size

        results = risk_export_data_query(query_string: "code-scanning-alerts:>0").query_data.data
        assert_equal 2, results.size
      end

      test "run returns all org data (does not paginate)" do
        org = create(:organization, name: "org-name", admin: @owner)
        5.times do |i|
          create_repo("#{org.display_login}-#{i}", owner: org, dbot_count: 1, cs_count: 2, ss_count: 3)
        end

        results = Export::DataQuery.stub_const(:PAGE_SIZE, 1) do
          risk_export_data_query(scope: org).run(list_data_query: create_list_data_query(organization: org))
        end

        assert_equal 5, results.size
      end

      test "run_for_single_page returns one page of data" do
        org = create(:organization, name: "org-name", admin: @owner)
        5.times do |i|
          create_repo("#{org.display_login}-#{i}", owner: org, dbot_count: 1, cs_count: 2, ss_count: 3)
        end

        results = Export::DataQuery.stub_const(:PAGE_SIZE, 1) do
          risk_export_data_query(scope: org).run_for_single_page(list_data_query: create_list_data_query(organization: org), page: 1)
        end

        assert_equal 1, results.size
      end

      test "throws DataLimitExceededError if number of repos exceeds page limit" do
        org = create(:organization, name: "org-name", admin: @owner)
        5.times do |i|
          create_repo("#{org.display_login}-#{i}", owner: org, dbot_count: 1, cs_count: 2, ss_count: 3)
        end

        Export::DataQuery.stub_const(:REPO_LIMIT, 1) do
          assert_raises(Export::DataQuery::DataLimitExceededError) do
            risk_export_data_query(scope: org).run(list_data_query: create_list_data_query(organization: org))
          end
        end
      end

      context "topics" do
        test "doesn't batch topics if cap limit is not hit" do
          org = create(:organization, name: "org-name", admin: @owner)

          (3).times do |i|
            repo = create_repo("#{org.display_login}-#{i}", owner: org, dbot_count: 1, cs_count: 2, ss_count: 3)
          end

          RepositoryTopic.expects(:names_for).once.returns(
            org.repositories.map { |repo| [repo.id, ["rand-topic"]] }.to_h
          )

          RepositoryTopic.stub_const(:DEFAULT_APPLIED_TO_LIMIT, 5) do
            RepositoryTopic.stub_const(:LIMIT_PER_REPOSITORY, 1) do
              risk_export_data_query(scope: org).run(list_data_query: create_list_data_query(organization: org))
            end
          end
        end

        test "batches topics to avoid RepositoryTopic limits" do
          org = create(:organization, name: "org-name", admin: @owner)

          (15).times do |i|
            repo = create_repo("#{org.display_login}-#{i}", owner: org, dbot_count: 1, cs_count: 2, ss_count: 3)
            5.times do
              create(:repository_topic, topic: create(:topic), repository: repo)
            end
          end

          RepositoryTopic.stub_const(:DEFAULT_APPLIED_TO_LIMIT, 10) do
            RepositoryTopic.stub_const(:LIMIT_PER_REPOSITORY, 5) do
              results = risk_export_data_query(scope: org).run(list_data_query: create_list_data_query(organization: org))
              results.each do |result|
                assert_equal 5, result.topics.size
              end
            end
          end
        end
      end

      context "teams" do
        test "filters teams to those with write and admin permission on the repo" do
          org = create(:organization, name: "org-name", admin: @owner)
          admin_team = create(:team, organization: org, name: "team-admin")
          write_team = create(:team, organization: org, name: "team-write")
          read_team = create(:team, organization: org, name: "team-read")
          3.times do |i|
            create_repo("#{org.display_login}-repo-#{i}", owner: org, dbot_count: 1, cs_count: 2, ss_count: 3).tap do |repo|
              write_team.add_repository(repo, :write)
              admin_team.add_repository(repo, :admin)
              read_team.add_repository(repo, :read)
            end
          end

          results = risk_export_data_query(scope: org).run(list_data_query: create_list_data_query(organization: org))
          results.each do |result|
            assert_same_elements [admin_team.slug, write_team.slug], result.teams
          end
        end

        test "filters teams to those visible to user" do
          org = create(:organization, name: "org-name", admin: @owner)

          user = create(:user)
          org.add_member(user)

          visible_team = create(:team, organization: org, name: "visible team", privacy: :closed)
          secret_team = create(:team, organization: org, name: "secret team", privacy: :secret)
          secret_team_with_user = create(:team, organization: org, name: "secret team with user", privacy: :secret)

          secret_team_with_user.add_member(user)

          create_repo("#{org.display_login}-repo", owner: org, dbot_count: 1, cs_count: 2, ss_count: 3).tap do |repo|
            visible_team.add_repository(repo, :admin)
            secret_team.add_repository(repo, :admin)
            secret_team_with_user.add_repository(repo, :admin)
          end

          results = risk_export_data_query(scope: org, user: user).run(list_data_query: create_list_data_query(organization: org))
          assert_equal 1, results.size

          results.first.tap do |result|
            assert_same_elements [visible_team.slug, secret_team_with_user.slug], result.teams
          end
        end

        test "limits number of teams per repo" do
          org = create(:organization, name: "org-name", admin: @owner)
          repo = create_repo("#{org.display_login}-repo", owner: org, dbot_count: 1, cs_count: 2, ss_count: 3)

          (SecurityCenter::Risk::ExportCsvGenerator::ELEMENT_COUNT_CAP + 1).times do |i|
            create(:team, organization: org, name: "team-#{i}").tap do |team|
              team.add_repository(repo, :admin)
            end
          end

          expected_teams = repo.teams.pluck(:slug).sort.first(SecurityCenter::Risk::ExportCsvGenerator::ELEMENT_COUNT_CAP)
          results = risk_export_data_query(scope: org).run(list_data_query: create_list_data_query(organization: org))
          results.each do |result|
            assert_same_elements expected_teams, result.teams
          end
        end
      end

      private

      sig do
        params(
          scope: T.any(Organization, Business),
          user: User,
          query_string: String,
          allowed_repository_ids_by_feature: T.nilable(T::Hash[Symbol, T::Array[Integer]]),
          authorized_orgs: T::Array[Organization]
        ).returns(Risk::ExportDataQuery)
      end
      def risk_export_data_query(scope: @org, user: @owner, query_string: "", allowed_repository_ids_by_feature: nil, authorized_orgs: [scope])
        # Because we can't instantiate an abstract class, we use a subclass to test functionality
        Risk::ExportDataQuery.new(
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

      sig do
        params(
          user: User,
          organization: Organization,
          parser: ::Orgs::SecurityCenter::RiskController::RiskQueryParser,
          repo_ids_by_feature: T.nilable(T::Hash[Symbol, T::Array[Integer]])
        )
        .returns(Risk::ListDataQuery)
      end
      def create_list_data_query(user: @owner, organization: @org, parser: ::Orgs::SecurityCenter::RiskController::RiskQueryParser.new(""), repo_ids_by_feature: nil)
        Risk::ListDataQuery.for_organization(
          user:,
          organization:,
          page_size: Export::DataQuery::PAGE_SIZE,
          parser:,
          repo_ids_by_feature:,
        )
      end
    end
  end
end
