# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class TeamMentionFilter < NodeFilter
    include GitHub::Goomba::Reference::Helpers
    SELECTOR = Goomba::Selector.new(match: "gh|team-mention")

    def initialize(*args)
      super
      @team_cache = {}
    end

    def selector
      SELECTOR
    end

    def async_scan
      Promise.all(@nodes.map do |node|
        org_login, team_slug = node["org"], node["team"]

        next unless repository || organization
        next unless org = organization || repository.organization
        next unless org.display_login.downcase == org_login.downcase

        Platform::Loaders::TeamBySlug.load(org, team_slug).then do |team|
          next unless team
          @team_cache[team_slug] = team
        end
      end).then do
        result[:mentioned_teams] = @team_cache.values.uniq.compact
      end
    end

    def call(node)
      org_login, team_slug = node["org"], node["team"]

      unlinked = EscapeHelper.safe_join(["@", org_login, "/", team_slug])

      return unlinked unless repository || organization
      return unlinked unless org = organization || repository.organization
      return unlinked unless org.display_login.downcase == org_login.downcase
      return unlinked unless team = @team_cache[team_slug]

      organization_resource_reference_wrapper(team) do |wrapper|
        wrapper.authorized { mentioned_team_html(team, org.display_login) }
        wrapper.unauthorized { unlinked }
      end
    end

    private

    def organization
      context[:organization]
    end

    def mentioned_team_html(team, org_login)
      team_path = "#{GitHub.url}/orgs/#{org_login}/teams/#{team.to_param}"
      ajax_path = "/orgs/#{org_login}/teams/#{team.to_param}/members"

      attrs = {
        "class": "team-mention js-team-mention notranslate",
        "data-error-text": "Failed to load team members",
        "data-id": team.id,
        "data-permission-text": "Team members are private",
        "data-url": ajax_path,
      }
      hovercard_attrs = HovercardHelper.hovercard_data_attributes_for_org_and_team(
        org_login, team.slug
      )
      hovercard_attrs.each do |key, value|
        attrs["data-#{key}"] = value
      end
      ActionController::Base.helpers.link_to(EscapeHelper.safe_join(["@", org_login, "/", team.slug]), team_path, attrs)
    end
  end
end
