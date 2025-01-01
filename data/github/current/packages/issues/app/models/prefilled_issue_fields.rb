# typed: true
# frozen_string_literal: true

# Public: Loads Issue (or Pull Request, conceptually) association objects for
#         pre-filling in the new Issue or new PR forms, based on query params.
#
class PrefilledIssueFields
  include GitHub::ResilienceMixin
  include Scientist

  # See also: Issue::MAX_ASSIGNEES.
  MAX_ASSIGNEES_FROM_PARAMS = 10
  MAX_LABELS_FROM_PARAMS = 20
  MAX_PROJECTS_FROM_PARAMS = 20

  attr_reader :params, :repository, :user, :warnings

  # Public: Initialize a new PrefilledIssueFields object.
  #
  # params - A StrongParams instance passed from a controller action.
  # repository - The current Repository, where an Issue will exist.
  # user - The current User, responsible for the Issue.
  #
  # Returns a PrefilledIssueFields instance.
  def initialize(params:, repository:, user:)
    @params = params
    @repository = repository
    @user = user
    @warnings = []
  end

  # Public: A body String from params.
  #
  # Reads from params[:body], a discussion body loaded from
  # params[:created_from_discussion_number], and params[:permalink].
  #
  # If neither :body, a loaded discussion body, nor :permalink is present, returns nil.
  #
  # If one of them is present, returns it. If all are present,
  # returns the :body value, then the discussion body, then :permalink value
  # separated by a newline.
  #
  # Returns a String or nil.
  def body
    return unless has_body_params?

    body_elements = []
    body_elements << params[:body] if params[:body].present?
    body_elements << discussion_body if discussion_body.present?
    body_elements << params[:permalink] if params[:permalink].present?

    body_elements.compact.join("\n\n")
  end

  # Public: Returns the String name of a body template if present in params.
  #
  # Reads from params[:template].
  #
  # Returns a String or nil.
  def template
    params[:template]
  end

  # Public: A title String from params.
  #
  # Read from params[:title] or the discussion that the issue is created from.
  #
  # Returns a String or nil.
  def title
    params[:title] || discussion&.title
  end

  # Public: A Milestone record from params.
  #
  # Reads one value from params[:milestone].
  #
  # If the value of params[:milestone] looks like a number, will attempt
  # to find the Milestone of that number.
  #
  # If it looks like a text string, will attempt to find the Milestone
  # with that title. The title and param will be downcased before comparing.
  #
  # Returns a Milestone or nil.
  def milestone
    return unless params[:milestone]

    milestone_param = params[:milestone].to_s.strip

    # Attempt to treat milestone param as the milestone number
    if /\A[1-9]\d{0,}\z/ =~ milestone_param
      found = repository.milestones.open_milestones.where(number: milestone_param.to_i).first
      return found if found
    end

    # Fall back to looking up by title; measure the frequency of use for possible removal
    repository.milestones.open_milestones.detect { |m| m.title.downcase == milestone_param.downcase }
  end

  # Public: A collection of assignable User records from query params.
  #
  # Will return up to MAX_ASSIGNEES_FROM_PARAMS records from the current_repository.
  #
  # Reads from params[:assignees] and params[:assignee].
  #
  # For params[:assignees], understands a comma-separated String, such as
  # "&assignees=octocat,hubot".
  #
  # For params[:assignee], expects a single login String.
  #
  # Returns an Array of Users.
  def assignees
    logins = split_params_string(field: :assignees, limit: MAX_ASSIGNEES_FROM_PARAMS)
    if params[:assignee].to_s.present?
      logins << params[:assignee].to_s.strip if logins.count < MAX_ASSIGNEES_FROM_PARAMS
    end
    return [] if logins.empty?

    users = User.where(login: logins).to_a
    valid_ids = repository.filtered_available_assignee_ids(actor_ids_filter: users.map(&:id))
    users.select { |user| valid_ids.include?(user.id) }
  end

  # Public: A collection of Label records from the repository from query params.
  #
  # Will return up to MAX_LABELS_FROM_PARAMS records from the current_repository.
  #
  # Reads from the discussion that the issue is being created from, or params[:labels].
  #
  # Understands a comma-separated String, such as "&labels=foo,bar".
  #
  # Returns an Array of Labels.
  def labels(user_can_label: true, allowed_labels: [])
    return @labels if defined?(@labels)

    if params[:labels].present?
      names = split_params_string(field: :labels, limit: MAX_LABELS_FROM_PARAMS)
      return @labels = [] if names.empty?

      if user_can_label
        @labels = repository.labels.where(name: names).limit(MAX_LABELS_FROM_PARAMS).to_a
      else
        # If the user can't label, only template defined labels are allowed
        @labels = repository.labels.merge(allowed_labels)
      end
    else
      @labels = discussion_labels
    end
  end

  # Public: A collection of Project records from the repo / org from query params.
  #
  # Will return up to MAX_PROJECTS_FROM_PARAMS records from the current_repository
  # or its Organization, if the repository belongs to an org.
  #
  # Reads from params[:projects].
  #
  # Expects signifier Strings like the following:
  #
  #    org/123
  #    user/repo/123
  #    org/repo/123
  #
  # Understands a comma-separated String, such as "&projects=org/123,org/repo/456".
  #
  # Returns an Array of Projects.
  def projects
    project_params = split_params_string(field: :projects, limit: MAX_PROJECTS_FROM_PARAMS)
    return Project.none if project_params.empty?

    owner = repository.owner
    parsed_params = project_params.map do |param|
      ProjectQueryParam.new(param: param, repository: repository, owner: owner)
    end

    parsed_params.select!(&:valid?)
    return Project.none if parsed_params.empty?

    repo_owned, non_repo_owned = parsed_params.partition(&:repository_project?)
    projects = []

    if non_repo_owned.present?
      numbers = non_repo_owned.map(&:number)
      projects << owner.writable_projects_for(user).open_projects.where(number: numbers)
    end

    if repo_owned.present?
      numbers = repo_owned.map(&:number)
      projects << repository.writable_projects_for(user).open_projects.where(number: numbers)
    end

    projects = projects.map(&:to_a).flatten

    return Project.none if projects.empty?
    projects
  end

  # Public: A collection of Memex Project records from the org or user from query params.
  #
  # Will return up to MAX_PROJECTS_FROM_PARAMS records from organizations or users.
  #
  # Reads from params[:projects].
  #
  # Expects signifier Strings like the following:
  #
  #    org/123
  #    monalisa/123
  #
  # Understands a comma-separated String, such as "&projects=org/123,org/456".
  #
  # Returns an Array of Memex Projects.
  def memex_projects
    memex_projects_for_viewer(user)
  end

  def memex_projects_for_viewer(viewer)
    memex_project_params = split_params_string(field: :projects, limit: MAX_PROJECTS_FROM_PARAMS)
    return MemexProject.none if memex_project_params.empty?

    memex_projects = []
    project_numbers = []
    repo_owner = repository.owner
    memex_project_params.map do |param|
      owner_name, number = param.split("/")
      next unless owner_name.present? && number.present?
      next unless owner_name == repo_owner.display_login

      project_numbers << number
    end

    return MemexProject.none if project_numbers.empty?

    projects = with_database_error_fallback(fallback: -> {
      @warnings << { attribute: :memex_projects, type: :database_error }
      []
    }) do
      repo_owner.memex_projects.active_projects.where(number: project_numbers).to_a
    end

    promises = projects.map do |project|
      project.async_viewer_can_write?(viewer).then do |can_write|
        [project, can_write]
      end
    end

    results = Promise.all(promises).sync
    results.select { |_, can_write| can_write }.map(&:first).each do |project|
      memex_projects << project
    end

    memex_projects
  end

  # Returns a hash of the leftover params that might correspond to issue form fields
  def structured_template_inputs
    params.except(:body, :template, :title, :milestones, :assignees, :labels, :projects)
  end

  private

  # Private: Split an incoming string on commas, returning an Array of
  #          non-empty Strings.
  #
  # The returned Array will be up to limit in length.
  #
  # Returns an Array of Strings.
  def split_params_string(field:, limit: 10)
    return [] unless params[field]
    params[field].to_s.split(",").first(limit).each(&:strip!).select(&:present?)
  end

  # Private: Indicates if there are params that can be used to generate an
  #          issue body.
  #
  # Returns a Boolean.
  def has_body_params?
    params[:body] || discussion_body || params[:permalink]
  end

  # Private: Loads the associated discussion that the issue is being created from
  #          if params[:created_from_discussion_number] is present.
  #
  # Returns a Discussion|nil.
  def discussion
    return @discussion if defined?(@discussion)
    return @discussion = nil unless params[:created_from_discussion_number].present?
    return @discussion = nil unless repository.discussions_on?

    @discussion = repository.discussions.filter_spam_for(user).find_by(
      number: params[:created_from_discussion_number],
    )
  end

  # Private: Generates the body from the associated discussion that the issue is
  #          being created from.
  #
  # Returns a String|nil.
  def discussion_body
    return unless discussion.present?
    @discussion_body ||= DiscussionOpTextFormatter.new(discussion).format
  end

  # Private: Returns an Array of labels from the associated discussion
  #          that the issue is being created from.
  #
  # Returns an Array[Label].
  def discussion_labels
    return @discussion_labels if defined?(@discussion_labels)
    return @discussion_labels = [] unless discussion.present?

    @discussion_labels = discussion.labels.limit(MAX_LABELS_FROM_PARAMS).to_a
  end
end
