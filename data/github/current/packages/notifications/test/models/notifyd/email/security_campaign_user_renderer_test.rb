# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  module Email
    class SecurityCampaignUserRendererTest < GitHub::TestCase
      fixtures do
        @owner = create(:user, name: "org-owner")
        @org = create(:business_plus_organization, admin: @owner)

        @watched_repo_1 = create(:private_repository, owner: @org, from_example: :simple)
        @watched_repo_2 = create(:private_repository, owner: @org, from_example: :simple)
        @unwatched_repo = create(:private_repository, owner: @org, from_example: :simple)

        GitHub.newsies.subscribe_to_list(@owner, @watched_repo_1)
        GitHub.newsies.subscribe_to_list(@owner, @watched_repo_2)

        @campaign = create(:security_campaign, organization: @org)
        @campaign_user = create(:security_campaign_user, user: @owner, security_campaign: @campaign)

        2.times { create(:security_campaign_alert, security_campaign: @campaign, repository: @watched_repo_1) }
        3.times { create(:security_campaign_alert, security_campaign: @campaign, repository: @watched_repo_2) }
        4.times { create(:security_campaign_alert, security_campaign: @campaign, repository: @unwatched_repo) }
      end

      test "#render for create" do
        renderer = Notifyd::Email::SecurityCampaignUserRenderer.new(subject: @campaign_user, actor: @owner, operation: Notifyd::Operations::SecurityCampaignUserOperation::Create, context: {})

        layout = renderer.render

        assert_equal "<#{@org.name_with_display_owner}/security/campaigns/#{@campaign.number}@github.com>", layout.headers["Message-ID"]
        assert_equal @org.permalink, layout.headers["List-Archive"]
        assert_equal @owner.display_login, layout.headers["X-GitHub-Sender"]
        assert_equal "[#{@owner.name}] Security campaign #{@campaign.name} has been opened on your repositories", layout.subject
        assert_equal "#{@campaign.name} <#{@campaign.manager.name}@noreply.github.com>", layout.to
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
    end
  end
end
