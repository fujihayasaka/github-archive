# typed: true
# frozen_string_literal: true

class AutocompleteQuery
  # Public: Instantiates an autocomplete query based on the actor performing
  # the query and the query term itself. The autocomplete query can be altered
  # when an +organization+ or +friends+ are provided.
  #
  # actor          - The User who is performing the query.
  # query          - The String query to search for users by login or email.
  # organization:  - When an Organization is provided to the autocomplete query,
  #                  higher weight will be given to the organization members
  #                  the actor has permission to view when rendering the results.
  #
  #                  If no Organization is provided it will fallback to the users
  #                  the actor is following (optional).
  # friends:       - The Array of Users you want to give higher weight to in the
  #                  suggested results (optional).
  # include_teams: - Boolean that determines if the query will include teams
  #                  when bulk team actions are enabled and an organization
  #                  is present (optional).
  # business       - The Business instance when the query is being made in the
  #                  context of a business.
  #
  # org_members_only - If organization is supplied, this query will return only members of that organization
  #                    (returns only public members if actor not a member of the org, all org members otherwise)
  #
  # include_business_orgs - If org_members_only is supplied this will return only members
  #                         of the supplied organization's business.
  #
  # orgs_only      - Only return organizations. Used when finding suggested
  #                  organizations to invite to a business.
  #
  # with_orgs      - Whether to include orgs. Default: false
  # include_integration_installations: - Boolean that determines if the query will include integration_installations
  #                  when a repository is present (optional).
  # repository:    - The Repository instance when the query is being made in the
  #                  context of a integration installation.
  # exclude_suspended: - A boolean representing whether suspended users should
  #                      be excluded from suggestions, always true if actor is enterprise managed
  # prepend_friends - place favored friends (if any) at the front of the results or the back. Defaults to true.
  # include_outside_collaborators - If organization is supplied, the query will include any outside collaborators for repos
  #                                 belonging to the org. This will be further filtered by query string passed.
  # teams_only      - Only return teams. An organization must be provided. (optional)
  #
  # Returns AutocompleteQuery instance.
  def initialize(actor, query, organization: nil, friends: nil,
    include_teams: false, business: nil, org_members_only: false,
    include_business_orgs: false, orgs_only: false, with_orgs: false,
    businesses_only: false, include_integration_installations: nil,
    repository: nil, exclude_suspended: false, prepend_friends: true, include_outside_collaborators: false,
    teams_only: false
  )
    @actor = actor
    @query = query && query.strip
    @organization = organization
    @friends = friends
    @include_teams = !!include_teams
    @business = business
    @org_members_only = !!org_members_only
    @include_business_orgs = !!include_business_orgs
    @orgs_only = !!orgs_only
    @with_orgs = !!with_orgs
    @businesses_only = !!businesses_only
    @include_integration_installations = !!include_integration_installations
    @repository = repository
    @exclude_suspended = exclude_suspended || actor&.is_enterprise_managed?
    @prepend_friends = prepend_friends
    @include_outside_collaborators = !!include_outside_collaborators
    @teams_only = !!teams_only
  end

  def suggestions
    @suggestions ||= if @orgs_only
      org_suggestions
    elsif @businesses_only
      businesses_suggestions
    elsif @teams_only && @organization
      team_suggestions
    elsif @include_teams && @organization
      if @query.match("#{@organization.display_login}/") || @query.match("#{@organization}/")
        team_suggestions
      else
        team_suggestions + user_and_integration_installation_suggestions
      end
    else
      user_and_integration_installation_suggestions
    end
  end

  # Public: Determine if there are any suggestions to display.
  #
  # Returns true if suggestions are present, false otherwise.
  def suggestions?
    suggestions.any?
  end

  # Public: Determines if the query is suitable for an email invitation
  # when there are no user results and it matches the user email regex.
  #
  # Returns true if an email, false if not.
  def email_invitation?
    !suggestions? && email_query? && !@query.start_with?("mailto:")
  end

  def user_query?
    !email_query?
  end

  def email_query?
    User.valid_email?(@query)
  end

  # Public: can non-users be invited via email address, given the current
  # organization feature flags?
  #
  # Returns: Boolean
  def allow_email_invites?
    return false unless @organization.present?
    return false if @organization.enterprise_managed_user_enabled?
    !GitHub.bypass_org_invites_enabled?
  end

  def friends
    @friends ||= if @organization.present?
      @organization.visible_users_for(@actor)
    else
      # The `user_suggestions` method needs to know about an actor's friends
      # to promote relevant autocomplete results.

      # Because the friends that we are returning here are not filtered by the autocomplete query,
      # we need a limit that is high enough to be useful for the majority of users,
      # but also performant for users that follow a lot of accounts.
      @actor.following_for_viewer(@actor).limit(500)
    end
  end

  private

  def team_suggestions
    return [] if email_query?

    team_query = @query.sub("#{@organization.display_login}/", "").sub("#{@organization}/", "")
    TeamOverviewFilter.new(@organization, @actor, team_query).include_visible.results
  end

  def user_and_integration_installation_suggestions
    if @include_integration_installations && @repository.present?
      user_suggestions + integration_installation_suggestions
    else
      user_suggestions
    end
  end

  def user_suggestions
    start = GitHub::Dogstats.monotonic_time
    tags = []

    matching_users = User.search(
      @query,
      limit: 8,
      friends: friends,
      prepend_friends: @prepend_friends,
      org: @organization,
      with_orgs: @with_orgs,
      org_member_scope: org_member_scope,
      include_business_orgs: @include_business_orgs,
      exclude_suspended: @exclude_suspended,
      business: @business
    )
    blocked_users = @actor.ignored_by_any(matching_users)
    users = matching_users - blocked_users

    if @include_outside_collaborators
      tags = ["include_collaborators"]
      collaborators = @organization.outside_collaborators.like_login_or_profile_name(@query).order(id: :desc).limit(10)
      users = (users + collaborators).uniq
    end

    GitHub::PrefillAssociations.prefill_associations(users, [:profile, :two_factor_credential])

    users || []
  ensure
    time_elapsed = GitHub::Dogstats.duration(start)
    GitHub.dogstats.distribution("autocompletequery.user.suggestions", time_elapsed, tags: tags)
  end

  def integration_installation_suggestions
    query = @query.sub("[bot]", "")
    IntegrationInstallation.with_repository(@repository).includes(:integration).joins(:integration).limit(10).
                            merge(Integration.user_installable).
                            merge(Integration.name_or_slug_like(query))
  end

  def org_suggestions
    orgs = ::Organization.search(@query, limit: 10)
    GitHub::PrefillAssociations.prefill_associations(orgs, :profile)
    orgs
  end

  def org_member_scope
    return unless @org_members_only

    @organization.member?(@actor) ? :all : :public
  end

  def businesses_suggestions
    businesses = ::Business.search(@query, limit: 10)
    businesses
  end
end
