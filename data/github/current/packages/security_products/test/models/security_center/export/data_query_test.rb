# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Export
    class DataQueryTest < GitHub::TestCase

      fixtures do
        @owner = create(:user)
      end

      context "topics" do
        test "doesn't batch topics if cap limit is not hit" do
          org = create(:organization, name: "org-name", admin: @owner)

          (3).times do |i|
            repo = create(:private_repository, name: "#{org.display_login}-#{i}", owner: org)
          end

          RepositoryTopic.expects(:names_for).once.returns(
            org.repositories.map { |repo| [repo.id, ["rand-topic"]] }.to_h
          )

          RepositoryTopic.stub_const(:DEFAULT_APPLIED_TO_LIMIT, 5) do
            RepositoryTopic.stub_const(:LIMIT_PER_REPOSITORY, 1) do
              topics_by_repo_id = DataQuery.get_topics_by_repository_id(org.repository_ids)
              topics_by_repo_id.each do |_, topic_names|
                assert_same_elements ["rand-topic"], topic_names
              end
            end
          end
        end

        test "batches topics to avoid RepositoryTopic limits" do
          org = create(:organization, name: "org-name", admin: @owner)

          (15).times do |i|
            repo = create(:private_repository, name: "#{org.display_login}-#{i}", owner: org)
            5.times do
              create(:repository_topic, topic: create(:topic), repository: repo)
            end
          end

          RepositoryTopic.stub_const(:DEFAULT_APPLIED_TO_LIMIT, 10) do
            RepositoryTopic.stub_const(:LIMIT_PER_REPOSITORY, 5) do
              topics_by_repo_id = DataQuery.get_topics_by_repository_id(org.repository_ids)
              topics_by_repo_id.each do |_, topic_names|
                assert_equal 5, topic_names.size
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
            create(:private_repository, name: "#{org.display_login}-repo-#{i}", owner: org).tap do |repo|
              write_team.add_repository(repo, :write)
              admin_team.add_repository(repo, :admin)
              read_team.add_repository(repo, :read)
            end
          end

          teams_by_repo_id = DataQuery.get_teams_by_repository_id(
            org.repository_ids,
            [admin_team, write_team].map { |team| [team.id, team.slug] }.to_h,
            org,
            1
          )
          assert_equal org.repositories.count, teams_by_repo_id.size
          teams_by_repo_id.each do |_, team_slugs|
            assert_same_elements [admin_team.slug, write_team.slug], team_slugs
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

          create(:private_repository, name: "#{org.display_login}-repo", owner: org).tap do |repo|
            visible_team.add_repository(repo, :admin)
            secret_team.add_repository(repo, :admin)
            secret_team_with_user.add_repository(repo, :admin)
          end

          teams_by_repo_id = DataQuery.get_teams_by_repository_id(
            org.repository_ids,
            [visible_team, secret_team_with_user].map { |team| [team.id, team.slug] }.to_h,
            org,
            1
          )
          assert_equal 1, teams_by_repo_id.size
          teams_by_repo_id.each do |_, team_slugs|
            assert_same_elements [visible_team.slug, secret_team_with_user.slug], team_slugs
          end
        end

        test "limits number of teams per repo" do
          org = create(:organization, name: "org-name", admin: @owner)
          repo = create(:private_repository, name: "#{org.display_login}-repo", owner: org)

          (SecurityCenter::Risk::ExportCsvGenerator::ELEMENT_COUNT_CAP + 1).times do |i|
            create(:team, organization: org, name: "team-#{i}").tap do |team|
              team.add_repository(repo, :admin)
            end
          end

          expected_teams = repo.teams.pluck(:slug).sort.first(SecurityCenter::Risk::ExportCsvGenerator::ELEMENT_COUNT_CAP)

          teams_by_repo_id = DataQuery.get_teams_by_repository_id(
            org.repository_ids,
            org.teams.map { |team| [team.id, team.slug] }.to_h,
            org,
            1
          )
          assert_equal org.repositories.count, teams_by_repo_id.size
          teams_by_repo_id.each do |_, team_slugs|
            assert_same_elements expected_teams, team_slugs
          end
        end
      end
    end
  end
end
