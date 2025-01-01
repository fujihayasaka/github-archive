# typed: false
# frozen_string_literal: true

class RepositoryAccessList
  attr_reader :filter, :query, :role

  # Regex used to scan and obtain role values from filter query parameters
  MAIN_ROLE_REGEX = /role:(?<role_name>read|triage|write|maintain|admin)/
  CUSTOM_ROLE_REGEX = /role:'(?<role_name>(?:.*))'/
  ROLE_REGEX = Regexp.union(MAIN_ROLE_REGEX, CUSTOM_ROLE_REGEX)

  ORG_REPO_FILTER_REGEX = /filter:(?<filter_name>all|org_members|outside_collaborators|collaborators|teams|pending_invitations)/
  EMU_REPO_FILTER_REGEX = /filter:(?<filter_name>all|org_members|repository_collaborators|teams)/
  USER_REPO_FILTER_REGEX = /filter:(?<filter_name>all|collaborators|pending_invitations)/

  # query: A query parameter string with an optional action/role filter. For example "monalisa role:write".
  # Pagination:
  #   before or after denote either the login (for Users and Invitees) or slug (for Teams) at which to start
  #   or end the results.
  def initialize(repository:, current_user:, query: nil, filter: :all, before: nil, after: nil, limit: nil)
    raise ArgumentError ":before and :after cannot both be set" if before.present? && after.present?

    @repository = repository
    @query, @role, @filter = self.parse_query(query)
    @current_user = current_user
    @before = before
    @after = after
    @limit = limit
    @start_of_results = false
    @end_of_results = false
  end

  LIMIT_RANGE = 1..50
  DEFAULT_LIMIT = 10

  # Public: unified query for users and teams with direct access as well as repository invitations
  #
  # Returns an Array of AccessQueryMember objects
  def results
    return @results if defined? @results

    results =
      case @filter
      when :all
        direct_members + repository_teams + invitations
      when :outside_collaborators, :collaborators, :repository_collaborators
        direct_members
      when :org_members
        direct_members
      when :teams
        repository_teams
      when :pending_invitations
        invitations
      end

    results = sort(results)

    if @before.nil? && @after.nil?
      @start_of_results = true
    end

    # The algorithm to determine if we're at the beginning or end of the result set
    # is to request one more result than we need. If that number of results are available, then
    # we're not at the beginning or end, and we can trim off the extra result. If less than that
    # number are available, then we're at the beginning or end.
    if @before.present?
      results = results.last(limit + 1)
      if results.count < limit + 1
        @start_of_results = true
      else
        results = results.last(limit)
      end
    else # after is either present, or it's the first page
      results = results.take(limit + 1)
      if results.count < limit + 1
        @end_of_results = true
      else
        results = results.take(limit)
      end
    end

    @results = results
  end

  # Public: User objects that match the filter, query and pagination
  #
  # Returns an Array of Users
  def user_results
    return [] if @filter == :pending_invitations || @filter == :teams
    direct_members
  end

  # Public: all direct_members of this repository, with profile associations
  # prefilled.
  def direct_members
    return @direct_members if defined? @direct_members

    # Figure out if role is present, and if it's a legacy Ability action or a pre-defined
    # fine grained permission role
    if @role.present?
      if ::Ability.actions[@role]
        action = @role
      elsif Role.valid_system_role?(@role)
        role = Role.preset_by_name(@role)
      else
        role = RepositoryRole.custom_role_by_name(@role, org: @repository.owner)
      end
    end

    if (@filter == :org_members || @filter == :outside_collaborators || @filter == :repository_collaborators) && @repository.in_organization?
      case @filter
      when :outside_collaborators, :repository_collaborators
        member_ids = @repository.outside_collaborator_member_ids(action: @role)
      when :org_members
        member_ids = @repository.direct_org_member_ids(action: @role)
      end
    else # no filter is specified
      if role.present?
        member_ids = UserRole.where(role: role, target: @repository, actor_type: "User").pluck(:actor_id)
      else
        member_ids = @repository.member_ids(action: action)

        if ::Ability.actions[action] && role_to_remove = Role.preset_by_name(::Role::BASE_ACTION_FOR_ROLE[action])
          roles = Role.custom_roles_by_base_role(base_role: [Role.preset_by_name(action), role_to_remove], org: @repository.owner)
          role_member_ids_to_remove = UserRole.where(role: [Role.preset_by_name(action), role_to_remove, roles].flatten, target: @repository, actor_type: "User").pluck(:actor_id)
          member_ids = member_ids - role_member_ids_to_remove
        end
      end
    end

    return [] if member_ids.empty?

    scope = User.where(id: member_ids).includes(:profile)
    scope = scope.order(login: :asc)

    if @query.present?
      scope = scope.references(:profile)
        .where(["users.login LIKE :query OR profiles.name LIKE :query", { query: "%#{@query}%" }])
    end

    if @after.present?
      scope = scope.where("login > ?", @after)
    end

    if @before.present?
      scope = scope.where("login < ?", @before)
      scope = scope.reorder(login: :desc)
    end

    @direct_members = scope.limit(limit + 1)
  end

  def invitations
    user_invitations + email_invitations
  end

  # Private: every pending user invitation to this repository.
  def user_invitations
    return @pending_invitations if defined? @pending_invitations

    results = @repository.repository_invitations

    if @role.present?
      permission = RepositoryInvitation.permission_by_name_or_label(@role)
      if permission
        results = results.where(permissions: permission)
      else
        if Role.valid_system_role?(@role)
          role = Role.preset_by_name(@role)
        else
          role = RepositoryRole.custom_role_by_name(@role, org: @repository.owner)
        end
        results = results.with_roles(role) if role
      end
    end

    return @pending_invitations = results unless results.any?

    invitations = results.index_by(&:invitee_id)
    scope = User.where(id: invitations.keys).includes(:profile)
    scope = scope.order(login: :asc)

    if @after.present?
      scope = scope.where("login > ?", @after)
    end

    if @before.present?
      scope = scope.where("login < ?", @before)
      scope = scope.reorder(login: :desc)
    end

    if @query.present?
      scope = scope
        .where(["users.login LIKE :query OR profiles.name LIKE :query", { query: "%#{@query}%" }])
        .references(:profile)
    end

    users = scope.limit(limit + 1)
    results = users.map { |u| invitations[u.id] }

    @pending_invitations = results
  end

  # pending email invitations
  def email_invitations
    results = @repository.repository_invitations.where.not(email: nil)

    if @role.present?
      permission = RepositoryInvitation.permission_by_name_or_label(@role)
      if permission
        results = results.where(permissions: permission)
      else
        if Role.valid_system_role?(@role)
          role = Role.preset_by_name(@role)
        else
          role = RepositoryRole.custom_role_by_name(@role, org: @repository.owner)
        end
        results = results.with_roles(role) if role
      end
    end

    results = results.order(email: :asc)

    if @after.present?
      results = results.where("email > ?", @after)
    end

    if @before.present?
      results = results.where("email < ?", @before)
    end

    if @query.present?
      results = results
        .where(["email LIKE :query", { query: "%#{@query}%" }])
    end

    results = results.limit(limit + 1)

    results
  end

  # Public: Get all the teams that this repository is on that are visible to the
  # logged-in user.
  #
  # Returns an array of teams.
  def repository_teams
    return @teams if defined? @teams
    return @teams = [] unless @repository.in_organization?

    if @role.present?
      team_on_repo_with_role_ids = @repository.actor_ids_for_team_on_repo(action: @role)
      scope = @repository.organization.visible_teams_for(@current_user).where(id: team_on_repo_with_role_ids)
    else
      scope = @repository.visible_teams_for(@current_user)
    end

    scope = scope.order(slug: :asc)

    if query.present?
      scope = scope.where(["teams.name LIKE :query OR teams.slug LIKE :query OR teams.description LIKE :query", { query: "%#{@query}%" }])
    end

    if @after.present?
      scope = scope.where("slug > ?", @after)
    end

    if @before.present?
      scope = scope.where("slug < ?", @before)
      scope = scope.reorder(slug: :desc)
    end
    @teams = scope.limit(limit + 1)
  end

  def start_of_results?
    @start_of_results
  end

  def end_of_results?
    @end_of_results
  end

  # Public: the cursor to use to paginate to the page before the current query
  def before_cursor
    result_cursor(results.first)
  end

  # Public: the cursor to use to paginate to the page after the current query
  def after_cursor
    result_cursor(results.last)
  end

  private

  def sort(results)
    results.sort_by do |obj|
      case obj
      when User
        obj.display_login.downcase
      when Team
        obj.slug.downcase
      when RepositoryInvitation
        obj.invitee.present? ? obj.invitee.display_login.downcase : obj.email
      end
    end
  end

  def limit
    size = (@limit || DEFAULT_LIMIT).to_i
    if !LIMIT_RANGE.include?(size)
      size = @limit = DEFAULT_LIMIT
    end
    size
  end

  # Private: calculates the cursor (search key) for use in pagination
  def result_cursor(result)
    case result
    when User
      result.display_login
    when Team
      result.slug
    when RepositoryInvitation
      result.invitee.present? ? result.invitee.display_login : result.email
    else
      nil
    end
  end

  # Private: class method to extract a role, filter and query from a form query parameter
  #
  # Returns [cleaned_query, role, filter]
  # Where cleaned_query is a sanitized search phrase
  #       role is a symbol denoting an Ability action or Role
  #       filter is a symbol, defined in VALID_ORG_REPO_FILTERS or VALID_USER_REPO_FILTERS
  def parse_query(query)
    return [nil, nil, :all] unless query.present?

    role_match = (match = query.to_s.match(ROLE_REGEX)) && match[:role_name].to_sym
    after_role_query = role_match ? query.gsub(ROLE_REGEX, "").strip : query

    if @repository.in_organization?
      if @repository.is_enterprise_managed? && @repository.organization&.business&.emu_repository_collaborators_enabled?
        filter_regex = EMU_REPO_FILTER_REGEX
      else
        filter_regex = ORG_REPO_FILTER_REGEX
      end
    else
      filter_regex = USER_REPO_FILTER_REGEX
    end

    filter_match = (match = after_role_query.to_s.match(filter_regex)) && match[:filter_name].to_sym
    filter_match = :all if filter_match.nil?

    q = filter_match ? after_role_query.gsub(filter_regex, "").strip : after_role_query

    cleaned_query = ActiveRecord::Base.sanitize_sql_like(q || "").strip

    [cleaned_query, role_match, filter_match]
  end
end
