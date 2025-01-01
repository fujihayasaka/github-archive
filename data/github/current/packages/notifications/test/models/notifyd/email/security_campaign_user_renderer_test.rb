# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  module Email
    class SecurityCampaignUserRendererTest < GitHub::TestCase
      fixtures do
        make_trusted_oauth_apps_owner

        @owner = create(:user, name: "org-owner")
        @org = create(:business_plus_organization, admin: @owner)

        @user = create(:user, name: "user")
        @org.add_member(@user)
        @team = create(:team, organization: @org)
        @team.add_member(@user)

        @watched_repo_1 = create(:private_repository, owner: @org)
        @watched_repo_2 = create(:private_repository, owner: @org)
        @unwatched_repo = create(:private_repository, owner: @org)
        @inaccessible_repo = create(:private_repository, owner: @org)
        @inaccessible_repo_2 = create(:private_repository, owner: @org)

        @watched_repo_1.add_member(@user, action: :write)
        @watched_repo_2.add_team(@team, action: :write)
        @unwatched_repo.add_member(@user, action: :write)
        @inaccessible_repo.add_member(@user, action: :read)

        GitHub.newsies.subscribe_to_list(@user, @watched_repo_1)
        GitHub.newsies.subscribe_to_list(@user, @watched_repo_2)
        GitHub.newsies.subscribe_to_list(@user, @inaccessible_repo)
        GitHub.newsies.subscribe_to_list(@user, @inaccessible_repo_2)

        @campaign = create(:security_campaign, organization: @org)
        @campaign_user = create(:security_campaign_user, user: @user, security_campaign: @campaign)
      end

      setup do
        GitHub::Turboscan.stubs(:counts_by_repo)
          .returns(Twirp::ClientResp.new(
          data: Turboscan::Proto::CountsByRepoResponse.new({
            open_count: 5,
            closed_count: 2,
            repository_counts: [
              Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new({
                repository_id: @watched_repo_1.id,
                open_count: 1,
                closed_count: 1,
                open_with_links_count: 1,
              }),
              Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new({
                repository_id: @watched_repo_2.id,
                open_count: 0,
                closed_count: 1,
                open_with_links_count: 0,
              }),
              Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new({
                repository_id: @unwatched_repo.id,
                open_count: 1,
                closed_count: 1,
                open_with_links_count: 0,
              }),
              Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new({
                repository_id: @inaccessible_repo.id,
                open_count: 1,
                closed_count: 1,
                open_with_links_count: 1,
              }),
              Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new({
                repository_id: @inaccessible_repo_2.id,
                open_count: 1,
                closed_count: 1,
                open_with_links_count: 1,
              }),
            ],
          })
        ))

        @alert_counts_by_repo = {
          @watched_repo_1.id => 1,
          @watched_repo_2.id => 3,
          @unwatched_repo.id => 4,
          @inaccessible_repo.id => 10,
          @inaccessible_repo_2.id => 12,
        }
      end

      test "#render for create" do
        renderer = Notifyd::Email::SecurityCampaignUserRenderer.new(
          subject: @campaign_user,
          actor: @owner,
          operation: Notifyd::Operations::SecurityCampaignUserOperation::Create,
          alert_counts_by_repo: {},
        )

        layout = renderer.render

        assert_equal "<#{@org.name_with_display_owner}/security/campaigns/#{@campaign.number}@github.com>", layout.headers["Message-ID"]
        assert_equal @org.permalink, layout.headers["List-Archive"]
        assert_equal @owner.display_login, layout.headers["X-GitHub-Sender"]
        assert_equal "[#{@org.display_login}] Security campaign #{@campaign.name} has been opened on your repositories", layout.subject
        assert_equal "#{@user.name} <#{@org.display_login}@noreply.github.com>", layout.to
        assert_equal "GitHub", layout.from&.name
        assert_equal "noreply@noreply.#{GitHub.urls.smtp_domain}", layout.from&.email
        refute_nil layout.reasons_to_words
        refute_nil layout.unsubscribe_url_templates
        assert_equal Rails.application.routes.url_helpers.security_center_security_campaign_url(org: @org.name_with_display_owner, number: @campaign.number, email_source: "security_campaign_create", host: GitHub.url), layout.url

        assert_match @campaign.name, layout.body
        assert_match @campaign.name, layout.text_body

        assert_match "5 alerts", layout.body
        assert_match "5 alerts", layout.text_body

        [@watched_repo_1, @watched_repo_2].each do |repo|
          assert_match repo.name, layout.body
          assert_match repo.name, layout.text_body

          repo_campaign_url = Rails.application.routes.url_helpers.repository_security_campaign_url(repository: repo, user_id: @org.login, number: @campaign.number, email_source: "security_campaign_create", host: GitHub.url,)
          assert_match repo_campaign_url, layout.body
          assert_match repo_campaign_url, layout.text_body
        end

        assert_not_match @unwatched_repo.name, layout.body
        assert_not_match @unwatched_repo.name, layout.text_body
      end

      test "#render for create with multiple campaign managers" do
        manager = create(:user, login: "manager")
        other_manager = create(:user, login: "other-manager")
        another_manager = create(:user, login: "another-manager")
        @campaign.user_manager_users = [manager, other_manager, another_manager]

        renderer = Notifyd::Email::SecurityCampaignUserRenderer.new(
          subject: @campaign_user,
          actor: @owner,
          operation: Notifyd::Operations::SecurityCampaignUserOperation::Create,
          alert_counts_by_repo: {}
        )

        layout = renderer.render

        assert_match "@#{another_manager.name}, @#{manager.name}, and @#{other_manager.name}", layout.text_body
        assert_match "@#{another_manager.name}", layout.body
        assert_match Rails.application.routes.url_helpers.user_url(another_manager, host: GitHub.url), layout.body
        assert_match "@#{manager.name}", layout.body
        assert_match Rails.application.routes.url_helpers.user_url(manager, host: GitHub.url), layout.body
        assert_match "@#{other_manager.name}", layout.body
        assert_match Rails.application.routes.url_helpers.user_url(other_manager, host: GitHub.url), layout.body
      end

      test "#render for create with team campaign managers" do
        manager = create(:security_manager_team, organization: @org, name: "manager", privacy: :closed)
        other_manager = create(:security_manager_team, organization: @org, name: "other-manager", privacy: :closed)
        another_manager = create(:security_manager_team, organization: @org, name: "another-manager", privacy: :secret)
        another_manager.add_member(@user)
        secret_manager = create(:security_manager_team, organization: @org, name: "secret-manager", privacy: :secret)
        @campaign.user_manager_users = []
        @campaign.team_manager_team_ids = [manager.id, other_manager.id, another_manager.id, secret_manager.id]

        renderer = Notifyd::Email::SecurityCampaignUserRenderer.new(
          subject: @campaign_user,
          actor: @owner,
          operation: Notifyd::Operations::SecurityCampaignUserOperation::Create,
          alert_counts_by_repo: {}
        )

        layout = renderer.render

        assert_match "@#{@org.display_login}/#{another_manager.slug}, @#{@org.display_login}/#{manager.slug}, and @#{@org.display_login}/#{other_manager.slug}", layout.text_body
        assert_match "@#{@org.display_login}/#{another_manager.slug}", layout.body
        assert_match Rails.application.routes.url_helpers.team_url(@org, another_manager, host: GitHub.url), layout.body
        assert_match "@#{@org.display_login}/#{manager.slug}", layout.body
        assert_match Rails.application.routes.url_helpers.team_url(@org, manager, host: GitHub.url), layout.body
        assert_match "@#{@org.display_login}/#{other_manager.slug}", layout.body
        assert_match Rails.application.routes.url_helpers.team_url(@org, other_manager, host: GitHub.url), layout.body
      end

      test "#render for create with user and team campaign managers" do
        manager = create(:user, login: "manager")
        other_manager = create(:user, login: "other-manager")
        team_manager = create(:security_manager_team, organization: @org, name: "yet-another-manager", privacy: :closed)
        another_team_manager = create(:security_manager_team, organization: @org, name: "another-manager", privacy: :closed)
        @campaign.user_manager_user_ids = [manager.id, other_manager.id]
        @campaign.team_manager_team_ids = [team_manager.id, another_team_manager.id]

        renderer = Notifyd::Email::SecurityCampaignUserRenderer.new(
          subject: @campaign_user,
          actor: @owner,
          operation: Notifyd::Operations::SecurityCampaignUserOperation::Create,
          alert_counts_by_repo: {}
        )

        layout = renderer.render

        assert_match "@#{@org.display_login}/#{another_team_manager.slug}, @#{manager.display_login}, @#{other_manager.display_login}, and @#{@org.display_login}/#{team_manager.slug}", layout.text_body
        assert_match "@#{@org.display_login}/#{another_team_manager.slug}", layout.body
        assert_match Rails.application.routes.url_helpers.team_url(@org, another_team_manager, host: GitHub.url), layout.body
        assert_match "@#{manager.display_login}", layout.body
        assert_match Rails.application.routes.url_helpers.user_url(manager, host: GitHub.url), layout.body
        assert_match "@#{other_manager.display_login}", layout.body
        assert_match Rails.application.routes.url_helpers.user_url(other_manager, host: GitHub.url), layout.body
        assert_match "@#{@org.display_login}/#{team_manager.slug}", layout.body
        assert_match Rails.application.routes.url_helpers.team_url(@org, team_manager, host: GitHub.url), layout.body
      end

      test "#render for overdue" do
        renderer = Notifyd::Email::SecurityCampaignUserRenderer.new(
          subject: @campaign_user,
          actor: GitHub.trusted_oauth_apps_owner,
          operation: Notifyd::Operations::SecurityCampaignUserOperation::Overdue,
          alert_counts_by_repo: @alert_counts_by_repo,
        )

        layout = renderer.render

        assert_equal "<#{@org.name_with_display_owner}/security/campaigns/#{@campaign.number}@github.com>", layout.headers["Message-ID"]
        assert_equal @org.permalink, layout.headers["List-Archive"]
        assert_equal GitHub.trusted_oauth_apps_owner.display_login, layout.headers["X-GitHub-Sender"]
        assert_equal "[#{@org.display_login}] Security campaign #{@campaign.name} is overdue", layout.subject
        assert_equal "#{@user.name} <#{@org.display_login}@noreply.github.com>", layout.to
        assert_equal "GitHub", layout.from&.name
        assert_equal "noreply@noreply.#{GitHub.urls.smtp_domain}", layout.from&.email
        refute_nil layout.reasons_to_words
        refute_nil layout.unsubscribe_url_templates
        assert_equal Rails.application.routes.url_helpers.security_center_security_campaign_url(org: @org.name_with_display_owner, number: @campaign.number, email_source: "security_campaign_overdue", host: GitHub.url), layout.url

        assert_match @campaign.name, layout.body
        assert_match @campaign.name, layout.text_body

        assert_match "4 open alerts", layout.body
        assert_match "4 open alerts", layout.text_body

        [@watched_repo_1, @watched_repo_2].each do |repo|
          assert_match repo.name, layout.body
          assert_match repo.name, layout.text_body

          repo_campaign_url = Rails.application.routes.url_helpers.repository_security_campaign_url(repository: repo, user_id: @org.login, number: @campaign.number, email_source: "security_campaign_overdue", host: GitHub.url,)
          assert_match repo_campaign_url, layout.body
          assert_match repo_campaign_url, layout.text_body
        end

        assert_not_match @unwatched_repo.name, layout.body
        assert_not_match @unwatched_repo.name, layout.text_body
        assert_not_match @inaccessible_repo.name, layout.body
        assert_not_match @inaccessible_repo.name, layout.text_body
        assert_not_match @inaccessible_repo_2.name, layout.body
        assert_not_match @inaccessible_repo_2.name, layout.text_body
      end

      test "#render for overdue with multiple campaign managers" do
        manager = create(:user, login: "manager")
        other_manager = create(:user, login: "other-manager")
        another_manager = create(:user, login: "another-manager")
        @campaign.user_manager_users = [manager, other_manager, another_manager]

        renderer = Notifyd::Email::SecurityCampaignUserRenderer.new(
          subject: @campaign_user,
          actor: GitHub.trusted_oauth_apps_owner,
          operation: Notifyd::Operations::SecurityCampaignUserOperation::Overdue,
          alert_counts_by_repo: @alert_counts_by_repo,
        )

        layout = renderer.render

        assert_match "@#{another_manager.name}, @#{manager.name}, and @#{other_manager.name}", layout.text_body
        assert_match "@#{another_manager.name}", layout.body
        assert_match Rails.application.routes.url_helpers.user_url(another_manager, host: GitHub.url), layout.body
        assert_match "@#{manager.name}", layout.body
        assert_match Rails.application.routes.url_helpers.user_url(manager, host: GitHub.url), layout.body
        assert_match "@#{other_manager.name}", layout.body
        assert_match Rails.application.routes.url_helpers.user_url(other_manager, host: GitHub.url), layout.body
      end

      test "#render for overdue with team campaign managers" do
        manager = create(:security_manager_team, organization: @org, name: "manager", privacy: :closed)
        other_manager = create(:security_manager_team, organization: @org, name: "other-manager", privacy: :closed)
        another_manager = create(:security_manager_team, organization: @org, name: "another-manager", privacy: :secret)
        another_manager.add_member(@user)
        secret_manager = create(:security_manager_team, organization: @org, name: "secret-manager", privacy: :secret)
        @campaign.user_manager_users = []
        @campaign.team_manager_team_ids = [manager.id, other_manager.id, another_manager.id, secret_manager.id]

        renderer = Notifyd::Email::SecurityCampaignUserRenderer.new(
          subject: @campaign_user,
          actor: GitHub.trusted_oauth_apps_owner,
          operation: Notifyd::Operations::SecurityCampaignUserOperation::Overdue,
          alert_counts_by_repo: @alert_counts_by_repo,
        )

        layout = renderer.render

        assert_match "@#{@org.display_login}/#{another_manager.slug}, @#{@org.display_login}/#{manager.slug}, and @#{@org.display_login}/#{other_manager.slug}", layout.text_body
        assert_match "@#{@org.display_login}/#{another_manager.slug}", layout.body
        assert_match Rails.application.routes.url_helpers.team_url(@org, another_manager, host: GitHub.url), layout.body
        assert_match "@#{@org.display_login}/#{manager.slug}", layout.body
        assert_match Rails.application.routes.url_helpers.team_url(@org, manager, host: GitHub.url), layout.body
        assert_match "@#{@org.display_login}/#{other_manager.slug}", layout.body
        assert_match Rails.application.routes.url_helpers.team_url(@org, other_manager, host: GitHub.url), layout.body
      end

      test "#render for overdue with user and team campaign managers" do
        manager = create(:user, login: "manager")
        other_manager = create(:user, login: "other-manager")
        team_manager = create(:security_manager_team, organization: @org, name: "yet-another-manager", privacy: :closed)
        another_team_manager = create(:security_manager_team, organization: @org, name: "another-manager", privacy: :closed)
        @campaign.user_manager_user_ids = [manager.id, other_manager.id]
        @campaign.team_manager_team_ids = [team_manager.id, another_team_manager.id]

        renderer = Notifyd::Email::SecurityCampaignUserRenderer.new(
          subject: @campaign_user,
          actor: GitHub.trusted_oauth_apps_owner,
          operation: Notifyd::Operations::SecurityCampaignUserOperation::Overdue,
          alert_counts_by_repo: @alert_counts_by_repo,
        )

        layout = renderer.render

        assert_match "@#{@org.display_login}/#{another_team_manager.slug}, @#{manager.display_login}, @#{other_manager.display_login}, and @#{@org.display_login}/#{team_manager.slug}", layout.text_body
        assert_match "@#{@org.display_login}/#{another_team_manager.slug}", layout.body
        assert_match Rails.application.routes.url_helpers.team_url(@org, another_team_manager, host: GitHub.url), layout.body
        assert_match "@#{manager.display_login}", layout.body
        assert_match Rails.application.routes.url_helpers.user_url(manager, host: GitHub.url), layout.body
        assert_match "@#{other_manager.display_login}", layout.body
        assert_match Rails.application.routes.url_helpers.user_url(other_manager, host: GitHub.url), layout.body
        assert_match "@#{@org.display_login}/#{team_manager.slug}", layout.body
        assert_match Rails.application.routes.url_helpers.team_url(@org, team_manager, host: GitHub.url), layout.body
      end
    end
  end
end
