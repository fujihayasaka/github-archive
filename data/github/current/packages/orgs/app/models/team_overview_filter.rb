# typed: true
# frozen_string_literal: true

# Find and filters a list of teams for a user
class TeamOverviewFilter
  REPO_REGEX = /repo:([\w\-\.]+)\/([\w\-\.]+)/
  USER_REGEX = /@([\w\-\.]+)/
  VISIBILITY_REGEX = /visibility:(secret|visible)/
  EMPTY_REGEX = /members:(empty|me)/

  RESULT_LIMIT = 10

  # Public: You know what this method does
  #
  # organization - the Organization whose teams we're looking at
  # user         - the User whose teams we care about
  # query        - a String that can filter out teams based on name, slug, repos or members
  def initialize(organization, user, query)
    @organization, @user, @query = organization, user, query
  end

  # Public: Include teams that are visible to the user as well as the teams the user is on.
  def include_visible
    @include_visible = true
    self
  end

  def results
    if @query.present?
      teams = []
      # If the query string specifies repos via the repo:owner/name syntax, only start
      # with teams that have access to those repositories
      if repositories_from_query.any?
        repositories_from_query.each { |repo| teams.concat repo.teams_for(@user) }
      else
        teams = teams_for_user
      end

      # If the query string specifies users via the @username syntax, only start with
      # teams that have those users as members
      if users_from_query.any?
        teams = teams.select do |team|
          users_from_query.all? { |user| team.member?(user) }
        end
      end

      teams = teams_by_visibility_filter(teams)
      teams = teams_by_members_filter(teams)

      prefix_matches = @organization.teams.
        where(id: teams.map(&:id)).
        where(["name LIKE ? OR slug LIKE ?", "#{cleaned_query}%", "#{cleaned_query}%"]).
        distinct.order(:name).limit(RESULT_LIMIT).
        to_a

      return prefix_matches if prefix_matches.count == RESULT_LIMIT

      fuzzy_matches = @organization.teams.
        where(id: teams.map(&:id) - prefix_matches.map(&:id)).
        where(["name LIKE ? OR slug LIKE ?", "%#{cleaned_query}%", "%#{cleaned_query}%"]).
        distinct.order(:name).limit(RESULT_LIMIT - prefix_matches.count)

      prefix_matches + fuzzy_matches
    else
      teams_for_user.order(:name).limit(RESULT_LIMIT).to_a
    end
  end

  private

  # If the query string specifies visibility by the visibility: syntax, return only
  # teams with the specified visibility
  def teams_by_visibility_filter(teams)
    @query.scan(VISIBILITY_REGEX) do |visibility|
      if visibility.join("") == "secret"
        teams = teams.secret
      elsif visibility.join("") == "visible"
        teams = teams.closed
      end
    end
    teams
  end

  # If the query string specifies filtering teams with the
  # members: syntax, return those teams
  def teams_by_members_filter(teams)
    @query.scan(EMPTY_REGEX) do |query_term|
      # return teams the user is a member of
      if query_term.join("") == "me"
        teams = teams.select { |team| team.members.include?(@user) }
      # return teams with no members
      elsif query_term.join("") == "empty"
        teams = teams.select { |team| team.members.empty? }
      end
    end
    teams
  end

  # Returns a base scope of teams we care about. If @include_visible is specified, we'll include the
  # teams that the user can see as well as the teams the user is on.
  def teams_for_user
    if @include_visible
      @organization.visible_teams_for(@user)
    else
      @organization.teams_for(@user)
    end
  end

  # Find repositories from the query string that match the repo:owner/name syntax
  def repositories_from_query
    @repositories_from_query ||= Set.new.tap do |repositories|
      @query.scan(REPO_REGEX) do |name, owner|
        if repo = @organization.repositories.with_name_with_owner("#{name}/#{owner}")
          repositories << repo
        end
      end
    end
  end

  # Find users from the query string that match the @username syntax
  def users_from_query
    @users_from_query ||= Set.new.tap do |users|
      @query.scan(USER_REGEX) do |name|
        if user = User.find_by_login(name.first) # String#scan returns arrays
          users << user
        end
      end
    end
  end

  # Return a String that strips repos/users so we can use it to match team names
  def cleaned_query
    ActiveRecord::Base.sanitize_sql_like(
      @query.gsub(REPO_REGEX, "").gsub(USER_REGEX, "").gsub(VISIBILITY_REGEX, "").gsub(EMPTY_REGEX, "").strip.downcase,
    )
  end
end
