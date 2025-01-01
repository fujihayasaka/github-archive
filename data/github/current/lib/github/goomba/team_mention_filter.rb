# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Text node filter that replaces @enterprise/team mentions with tooltipped links.
  # Mentions within <pre>, <code>, and <a> elements are ignored. Mentions that
  # reference orgs or teams that do not exist are ignored.
  #
  # Context options:
  #   N/A
  #
  # The following keys are written to the Result:
  #   :mentioned_teams - An array of Team objects that were mentioned.
  #
  class TeamMentionFilter < TextFilter
    IGNORE_PARENTS = GitHub::HTML::TeamMentionFilter::IGNORE_PARENTS.map { |p| "#{p} :text" }.join(", ")
    SELECTOR = Goomba::Selector.new(match: ":text", reject: IGNORE_PARENTS)

    def selector
      SELECTOR
    end

    def call(text)
      return nil unless text.html.include?("@")
      GitHub::HTML::TeamMentionFilter.mentioned_teams_in!(text.html) do |_match, org_login, team_slug|
        attrs = { org: org_login, team: team_slug }
        ActionController::Base.helpers.content_tag("gh:team-mention", nil, attrs)
      end
    end
  end
end
