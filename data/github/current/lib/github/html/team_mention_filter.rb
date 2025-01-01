# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # HTML filter that replaces @enterprise/team mentions with tooltipped links.
  # Mentions within <pre>, <code>, and <a> elements are ignored. Mentions that
  # reference orgs or teams that do not exist are ignored.
  #
  # Context options:
  #   N/A
  #
  # The following keys are written to the Result:
  #   :mentioned_teams - An array of Team objects that were mentioned.
  #
  class TeamMentionFilter < Filter
    # Public: Find team mentions in text -- team mentions follow the syntax
    # @org-name/team-slug. See TeamMentionFilter#mention_team_filter.
    #
    #   TeamMentionFilter.mentioned_teams_in(text) do |match, org, team|
    #     "<a href=...>#{org}/#{team}</a>"
    #   end
    #
    # text - String text to search.
    #
    # Yields the String match, the String org name, and the String team name.
    # The yield's return replaces the match in the original text.
    #
    # Returns nil if no mentions were found. Otherwise modifies text in-place and returns it.
    def self.mentioned_teams_in!(text)
      text.gsub! MentionPattern do |match|
        org  = $1
        team = $2
        yield match, org, team
      end
    end

    MentionPattern = /
      (?<=^|\W)                  # beginning of string or non-word char
      @([a-z0-9][a-z0-9-]*)      # @organization
        \/                       # dividing slash
        ([a-z0-9][a-z0-9\-_]*)   # team
        \b
    /ix

    # Don't look for mentions in text nodes that are children of these elements
    IGNORE_PARENTS = %w(pre code a).to_set

    def call
      return doc unless current_user
      mentioned_teams.clear
      doc.xpath(".//text()").each do |node|
        content = node.to_html
        next if !content.include?("@")
        next if has_ancestor?(node, IGNORE_PARENTS)
        html = mention_team_filter!(content)
        next if html.nil?
        node.replace(html)
      end
      mentioned_teams.uniq!
      doc
    end

    # List of Team objects that were mentioned in the document. This is
    # available in the context hash as :mentioned_teams.
    def mentioned_teams
      result[:mentioned_teams] ||= []
    end

    # Replace team @mentions in text with a span showing what users are in the team.
    #
    # text - String text to replace @mention team names in.
    #
    # Returns nil if no mentions were found. Otherwise modifies text in-place
    # and returns it with the replacements made. All links have a
    # 'team-mention' class name attached for styling.
    def mention_team_filter!(text)
      self.class.mentioned_teams_in!(text) do |match, org_login, team_slug|
        if team = find_team(team_slug, org_login)
          mentioned_teams << team
          mentioned_team_html(team)
        else
          match
        end
      end
    end

    # Internal: find the team, properly scoped for security
    #
    # Returns a Team object, or nil if no team is found
    def find_team(team_slug, org_login)
      return nil unless repository || organization
      return nil unless org = organization || repository.organization
      return nil unless org.login == org_login

      # we need to load the integration installation for the repository to determine
      # whether or not the team is visible to the integation

      if repository && current_user.bot?
        current_user.async_load_installation_for(repository).sync
      end
      org.find_team_by_slug(team_slug, visible_to: current_user)
    end

    # Internal: make a link for the mentioned team
    #
    # Returns a String
    def mentioned_team_html(team)
      team_path = "#{GitHub.url}/orgs/#{team.organization}/teams/#{team.to_param}"
      ajax_path = "/orgs/#{team.organization}/teams/#{team.to_param}/members"
      permission_text = "Team members are private"
      error_text = "Failed to load team members"
      hovercard_url = HovercardHelper.hovercard_url_for_org_and_team(
        team.organization.login, team.slug
      )
      %|<a class="team-mention js-team-mention" data-url="#{ajax_path}" data-id="#{team.id}" href="#{team_path}" data-error-text="#{error_text}" data-permission-text="#{permission_text}" data-hovercard-type="team" data-hovercard-url="#{hovercard_url}">@#{team.combined_slug}</a>|
    end
  end
end
