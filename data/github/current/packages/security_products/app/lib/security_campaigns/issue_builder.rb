# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class IssueBuilder
    include ActionView::Helpers::TextHelper
    include GitHub::Memoizer

    sig { params(security_campaign: SecurityCampaigns::SecurityCampaign, repository: Repository).void }
    def initialize(security_campaign:, repository:)
      @security_campaign = security_campaign
      @repository = repository
    end

    sig { returns(String) }
    def issue_title
      "[Security campaign tracking] #{@security_campaign.name}"
    end

    sig { returns(String) }
    def issue_body
      text_template_file = Rails.root.join("packages", "security_products", "app", "models", "security_campaigns", "templates", "issue_body.text.erb")

      ERB.new(File.read(text_template_file), trim_mode: "%<>").result(binding)
    end

    sig { params(bot_name: String).returns(String) }
    def updated_issue_body(bot_name)
      "#{issue_body} \n\n _These campaign details have been edited by the #{bot_name} bot._"
    end

    private

    sig { returns(String) }
    def repo_level_url
      UrlHelpers.repository_security_campaign_url(
        host: GitHub.url,
        repository: @repository,
        user_id: @repository.owner_display_login,
        number: @security_campaign.number)
    end

    sig { returns(T::Enumerable[T.any(User, Team)]) }
    memoize def managers
      (@security_campaign.user_manager_users + @security_campaign.team_manager_teams.not_secret).compact.sort_by do |manager|
        if manager.is_a?(User)
          manager.display_login
        else
          manager.slug
        end
      end
    end

    sig { params(manager: T.any(User, Team)).returns(String) }
    def manager_name(manager)
      if manager.is_a?(User)
        "@#{manager.display_login}"
      else
        "@#{T.must(manager.organization).display_login}/#{manager.slug}"
      end
    end

    sig { params(manager: T.any(User, Team)).returns(String) }
    def manager_url(manager)
      if manager.is_a?(User)
        Rails.application.routes.url_helpers.user_url(manager, host: GitHub.url)
      else
        Rails.application.routes.url_helpers.team_url(manager.organization, manager, host: GitHub.url)
      end
    end

    sig { params(text: String).returns(String) }
    def escape_markdown(text)
      # Escape characters that are used in markdown formatting
      # Add a zero-width space after @ to prevent mentions
      text.gsub(/([*\[\]()`_\\])/) { |m| "\\#{m}" }.gsub("<", "&lt;").gsub(">", "&gt;").gsub("@", "@&ZeroWidthSpace;")
    end
  end
end
