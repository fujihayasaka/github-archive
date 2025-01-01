# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  module Email
    class SecurityCampaignRepositoryRendererTest < GitHub::TestCase
      fixtures do
        @owner = create(:user, name: "org-owner")
        @org = create(:business_plus_organization, admin: @owner)

        @repo = create(:private_repository, owner: @org, from_example: :simple)
        @campaign = create(:security_campaign, organization: @org)
        @campaign_repository = create(:security_campaign_repository, repository: @repo, security_campaign: @campaign)

        10.times do
          create(:security_campaign_alert, security_campaign: @campaign, repository: @repo)
        end
      end

      test "#render for create" do
        renderer = Notifyd::Email::SecurityCampaignRepositoryRenderer.new(subject: @campaign_repository, actor: @owner, operation: Notifyd::Operations::SecurityCampaignRepositoryOperation::Create, context: {})

        layout = renderer.render

        assert_equal "<#{@repo.name_with_display_owner}/security/campaigns/#{@campaign.number}@github.com>", layout.headers["Message-ID"]
        assert_equal @repo.permalink, layout.headers["List-Archive"]
        assert_equal @owner.display_login, layout.headers["X-GitHub-Sender"]
        assert_equal "[#{@repo.name_with_display_owner}] Security campaign #{@campaign.name} has been opened on your repository", layout.subject
        assert_equal "#{@repo.name_with_display_owner} <#{@repo}@noreply.github.com>", layout.to
        assert_equal "GitHub", layout.from&.name
        assert_equal "noreply@noreply.#{GitHub.urls.smtp_domain}", layout.from&.email
        refute_nil layout.reasons_to_words
        refute_nil layout.unsubscribe_url_templates
        assert_equal "#{@campaign_repository.permalink}?email_source=security_campaign_create", layout.url

        assert_match @campaign.name, layout.body
        assert_match @campaign.name, layout.text_body
        assert_match "10 alerts", layout.body
        assert_match "10 alerts", layout.text_body
      end

      test "#render for overdue" do
        renderer = Notifyd::Email::SecurityCampaignRepositoryRenderer.new(subject: @campaign_repository, actor: @owner, operation: Notifyd::Operations::SecurityCampaignRepositoryOperation::Overdue, context: {
          open_alerts_count: 7,
        })

        layout = renderer.render

        assert_equal "<#{@repo.name_with_display_owner}/security/campaigns/#{@campaign.number}@github.com>", layout.headers["Message-ID"]
        assert_equal @repo.permalink, layout.headers["List-Archive"]
        assert_equal @owner.display_login, layout.headers["X-GitHub-Sender"]
        assert_equal "[#{@repo.name_with_display_owner}] Security campaign #{@campaign.name} is overdue", layout.subject
        assert_equal "#{@repo.name_with_display_owner} <#{@repo}@noreply.github.com>", layout.to
        assert_equal "GitHub", layout.from&.name
        assert_equal "noreply@noreply.#{GitHub.urls.smtp_domain}", layout.from&.email
        refute_nil layout.reasons_to_words
        refute_nil layout.unsubscribe_url_templates
        assert_equal "#{@campaign_repository.permalink}?email_source=security_campaign_overdue", layout.url

        assert_match @campaign.name, layout.body
        assert_match @campaign.name, layout.text_body
        assert_match "7 open alerts", layout.body
        assert_match "7 open alerts", layout.text_body
      end

      test "#render for overdue with missing open alerts count raises" do
        renderer = Notifyd::Email::SecurityCampaignRepositoryRenderer.new(subject: @campaign_repository, actor: @owner, operation: Notifyd::Operations::SecurityCampaignRepositoryOperation::Overdue, context: {})

        assert_raises_with_message(KeyError, "key not found: :open_alerts_count") do
          renderer.render
        end
      end

      test "#render for unknown operation raises" do
        renderer = Notifyd::Email::SecurityCampaignRepositoryRenderer.new(subject: @campaign_repository, actor: @owner, operation: Notifyd::Operations::SecurityCampaignRepositoryOperation::Unknown, context: {})

        assert_raises_with_message(ArgumentError, /Unknown operation/) do
          renderer.render
        end
      end
    end
  end
end
