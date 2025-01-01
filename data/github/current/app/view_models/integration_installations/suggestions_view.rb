# typed: true
# frozen_string_literal: true

class IntegrationInstallations::SuggestionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include GitHub::Memoizer

  REPOSITORY_SELECTION_OPTIONS = {
    "all" => :all,
    "subset" => :selected,
    "selected" => :selected,
    "none" => :none,
    nil => :none
  }

  MAX_SUGGESTIONS = 100

  attr_reader :target, :integration, :installation, :installation_request
  attr_reader :session
  attr_reader :query
  attr_reader :edit_installed_repositories
  attr_reader :exclude, :skip_installed_on_check
  attr_reader :referer
  attr_reader :programmatic_access
  attr_reader :programmatic_access_repository_selection_type
  attr_reader :programmatic_access_requested_repositories

  delegate :came_from_marketplace?, :marketplace_listing_id, :logo_background_color_style_rule,
           to: :installation_view

  def not_actionable_reason
    check = if !installable?
      # Special case contact email requirement because the Permissions check doesn't cover it.
      integration.installable_on_by(target: target, actor: current_user)
    else
      integration.requestable_on_by(target: target, actor: current_user)
    end

    check.reason
  end

  def installable?
    return @installable if defined?(@installable)
    @installable = integration.installable_on_by?(target: target, actor: current_user)
  end

  def cancel_path
    return referer || urls.marketplace_path if came_from_marketplace?

    # If the app is private, taking the user back to the `/new` page will
    # cause them to redirect back to the installation page for the only target
    # the user can install the app on.
    #
    # See https://github.com/github/ecosystem-apps/issues/2289
    return urls.gh_app_path(integration, current_user) if integration.private_visibility?

    # In the event the user doesn't have any organizations
    # this would have redirected them back to the same page.
    #
    # This will instead take the user to the app homepage.
    #
    # See https://github.com/github/ecosystem-apps/issues/554
    return urls.gh_app_path(integration, current_user) if logged_in? && current_user.organizations.none?

    urls.gh_new_app_installation_path(integration, current_user)
  end

  # Installation is only requestable if there are repos that can be requested.
  # Sometimes this is skipped because the target has too many repos. In this
  # case, it's necessary for a user to talk to an org admin directly who will
  # be able to install the App on the desired repos on their behalf.
  def requestable?
    !skip_requestable_repositories? &&
      integration.requestable_on_by?(target: target, actor: current_user)
  end

  def repository_installation_required?
    integration.repository_installation_required?(target)
  end

  # Requestable repositories are those the User do not admin but have access to via an owning Organization
  memoize def requestable_repository_ids
    return [] if skip_requestable_repositories?

    if integration
      return integration.requestable_repository_ids_on_by(
        target: target, actor: current_user, exclude_requested: false
      )
    end

    ProgrammaticAccessGrantRequest.accessible_repository_ids_on_by(target, current_user)
  end

  # For targets with large numbers of repositories it's too expensive to
  # calculate which repos a non org admin can request installation on and
  # requests don't complete in time. In these cases it's better to just disable
  # the request functionality and let users directly have their org admins do
  # the installation on their behalf. The "manual" installation request flow.
  def skip_requestable_repositories?
    # Businesses can't have repositories...yet.
    return false if target.is_a?(Business)

    target.present? && target.feature_enabled?(:installation_skip_requestable_repos) &&
      target.repository_ids.length > Integration::InstallationService::DEFAULT_MAX_REPOS
  end

  def requestable_repositories?
    requestable_repository_ids.any?
  end

  def installable_repository_ids
    return @installable_repository_ids if defined?(@installable_repository_ids)
    @installable_repository_ids = []

    return @installable_repository_ids unless integration.present?

    exclude_installed = !use_select_panel?

    @installable_repository_ids = integration.installable_repository_ids_on_by(target: target, actor: current_user, exclude_installed: exclude_installed)
  end

  memoize def installable_repositories?
    return false unless integration.present?
    integration.installable_repository_ids_on_by(target: target, actor: current_user, exclude_installed: false).any?
  end

  def add_email_form_url
    target.organization? ? urls.organization_emails_path(target) : urls.user_emails_path(target)
  end

  def suggestable_repositories
    repository_ids = requestable_repository_ids + installable_repository_ids

    if current_user.feature_enabled?(:suggest_only_accessible_repos_to_fg_actor)
      Repositories::Public.accessible_repositories(
        repository_ids: repository_ids,
        associated_repository_ids: current_user.associated_repository_ids(repository_ids:)
      )
    else
      Repositories::Public.load_repositories(repository_ids)
    end
  end

  def suggestions(limit: 100)
    return initial_suggestions unless query

    @suggestions ||= begin
      scope = suggestable_repositories

      if excluded_repository_ids.any?
        scope = scope.where("repositories.id NOT IN (?)", excluded_repository_ids)
      end

      # enforce a maximum cap
      limit = MAX_SUGGESTIONS if limit > MAX_SUGGESTIONS

      exact_match = scope.where("repositories.name = :query", query: query).first

      scope = scope.where("repositories.name like :query", query: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
      scope = scope.select([:id, :name, :owner_id, :parent_id, :public, :description, :source_id])
      scope = scope.order("repositories.name").limit(limit)

      scope.to_a.prepend(exact_match).uniq.compact
    end
  end

  def initial_suggestions
    @initial_suggestions ||= begin
      scope = suggestable_repositories

      scope.recently_updated.limit(20)
    end
  end

  def suggestions?
    suggestions.any?
  end

  def initial_repository_ids
    return [] if installation && installation.installed_on_all_repositories?
    ids = []
    ids.concat(installed_repositories.pluck(:id)) if edit_installed_repositories?
    ids.concat(installation_request.repository_ids) if installation_request_available?
    ids.concat(programmatic_access_selected_repositories.pluck(:id)) if integration.nil? # viewing PAT
    ids
  end

  def is_intial_repository?(repo)
    initial_repository_ids.include?(repo.id)
  end

  def excluded_repository_ids
    Array.wrap(exclude)
  end

  def suggestion_label(repo)
    return if target == current_user || integration.blank?
    case
    when installed_on?(repo)
      :installed
    when suggestions_permissions[repo.id] == :admin
      :request unless installable_repository?(repo)
    when suggestions_permissions[repo.id] == :read
      :request
    end
  end

  # Public: Whether the integration has been installed on the given repository.
  #
  # If the integration is installed on all repositories and not directly on the
  # given repository, returns false.
  #
  # Returns a Boolean.
  def installed_on?(repo)
    return false if skip_installed_on_check
    return false unless installation.present?
    return false if installation.installed_on_all_repositories?
    installation.repository_ids.include?(repo.id)
  end

  def was_granted_access_to?(repo)
    return false unless programmatic_access.present?
    grant = programmatic_access.grant
    return false unless grant
    return false if grant.installed_on_all_repositories?
    grant.repository_ids.include?(repo.id)
  end

  def events
    return @events if defined?(@events)

    @events = []
    return @events if integration.hook.nil?

    @events = integration.hook.events.map do |event|
      Hook::EventRegistry.for_event_type(event).display_name
    end.sort
  end

  def can_target_all_repositories?
    can_install_on_all_repositories? || can_request_on_all_repositories?
  end

  def can_install_on_all_repositories?
    return true unless integration.present?

    integration.installable_on_all_repositories_by?(target: target, actor: current_user)
  end

  def can_request_on_all_repositories?
    integration.requestable_on_by?(target: target, actor: current_user)
  end

  # Whether this install target radio input should be checked by default
  # as specified by the installation request.
  #
  # Defaults to false.
  def install_target_radio_checked?(install_target)
    # checks if an installation exists with selected repos
    return install_target == :selected if installation_with_selected_repositories? && !installation_request_available?
    return programmatic_access_install_target_radio_checked?(install_target) if programmatic_access
    # if no installation_request is available, defaults to :all
    return install_target == :all unless installation_request_available?

    case install_target
    when :all
      installation_request.request_all_repositories?
    when :selected
      installation_request.request_some_repositories?
    when :none
      installation_request.request_no_repositories?
    end
  end

  def programmatic_access_install_target_radio_checked?(install_target)
    install_target == programmatic_access_repository_selection
  end

  def target_grant
    @target_grant ||= programmatic_access.grant_for(target)
  end

  def programmatic_access_repository_selection
    @programmatic_access_repository_selection ||=
      if programmatic_access_repository_selection_type.present?
        REPOSITORY_SELECTION_OPTIONS[programmatic_access_repository_selection_type.to_s]
      else
        REPOSITORY_SELECTION_OPTIONS[target_grant&.repository_selection]
      end
  end

  def programmatic_access_selected_repositories
    return programmatic_access_requested_repositories if programmatic_access_requested_repositories
    return [] unless target_grant
    return [] if target_grant.installed_on_all_repositories?

    target_grant.repositories
  end

  def paid_marketplace_plan_purchased?
    installation_view.paid_marketplace_plan_purchased_by?(target)
  end

  def target_noun
    target.organization? ? "Organization" : "Account"
  end

  def current_and_future_owned_repositories_text
    if programmatic_access
      target.organization? ? "that you can access in this organization" : "you own"
    else
      "owned by the resource owner"
    end
  end

  def installation_request_available?
    installation_request.present? && (installable? || installation_request.ephemeral? && requestable?)
  end

  def installation_suggestion_available?
    installation_request&.ephemeral?
  end

  def caption
    available_actions = []
    available_actions << "Approve" if installation_request_available?
    available_actions << "Install" if installable?
    available_actions << "Authorize" if integration&.can_request_oauth_on_install?
    available_actions << "Request" if requestable?
    available_actions.to_sentence(two_words_connector: " & ", last_word_connector: ", & ")
  end

  def disabled_caption
    available_actions = []
    available_actions << "Approving"   if installation_request_available?
    available_actions << "Installing"  if installable?
    available_actions << "Authorizing" if integration&.can_request_oauth_on_install?
    available_actions << "Requesting"  if requestable?
    available_actions.join(" & ")
  end

  def installation_requester_name
    if installation_request.ephemeral?
      installation_request.integration.name
    else
      "@#{installation_request.requester.display_login}"
    end
  end

  def installation_request_verb
    return "requested" unless installation_request
    installation_request.ephemeral? ? "suggested" : "requested"
  end

  def installation_requester_url
    if installation_request.ephemeral?
      urls.gh_app_path(installation_request.integration, current_user)
    else
      urls.user_path(installation_request.requester)
    end
  end

  def label_title(text = nil)
    case (text ||= installation_request_verb)
    when "suggested"
      "Suggested for installation"
    when "request"
      "Requesting installation"
    else
      "Selected for installation"
    end
  end

  def installation_requested_at
    return Time.zone.now if installation_request.ephemeral?
    installation_request.created_at
  end

  def edit_installed_repositories?
    edit_installed_repositories && !installation.installed_on_all_repositories?
  end

  def installed_repositories
    return @installed_repositories if defined?(@installed_repositories)

    scope = if target.adminable_by?(current_user)
      installation.repositories
    else
      Repository
      .where(id: current_user.associated_repository_ids(min_action: :admin, repository_ids: installation.repository_ids))
      .active
    end

    @installed_repositories = scope.preload(:owner, :parent).select(:id, :name, :owner_id, :parent_id, :public, :source_id)
  end

  def installation_with_selected_repositories?
    installation.present? && installation.repository_installation_required? && !installation.installed_on_all_repositories?
  end

  def account_type
    case target
    when Business
      "enterprise account"
    when Organization
      "organization"
    else
      "personal account"
    end
  end

  def multi_user_install?
    target != current_user
  end

  def display_max_repositories_note?
    integration.nil?
  end

  def max_repositories
    return IntegrationInstallationsController::MAX_REPOSITORIES_ON_INITIAL_INSTALL if integration

    ProgrammaticAccessGrant::MAX_REPOSITORY_SUBSET_LIMIT
  end

  def repository_suggestions_path
    integration.present? ? installations_suggestions_path : user_access_token_suggestions_path
  end

  def use_select_panel?
    integration.blank? # new select panel is only available for FG PAT
  end

  def errors
    attributes[:errors] || {}
  end

  private

  def installable_repository?(repo)
    integration.installable_on_by?(target: target, actor: current_user, repository_ids: [repo.id])
  end

  def installation_view
    InstallationView.new(integratable: integration, session: session, current_user: current_user)
  end

  # Internal: Compute permissions on suggestions.
  #
  # Public repositories are assumed to have `:read` permission.
  #
  # Returns a Hash{repo_id Int => action Symbol}.
  def suggestions_permissions
    @suggestions_permissions ||=
      begin
        suggested_repo_ids = suggestions.pluck(:id)

        # establish readable public repositories
        perms = target.repositories.public_scope.
          where(id: suggested_repo_ids).pluck(:id).
          reduce({}) do |perms, id|
            perms[id] = :read
            perms
          end

        # determine action on private repositories
        repo_abilities = Authorization.service.most_capable_collaborator_abilities_from_actor(
          actor: current_user,
          subject_type: Repository,
          subject_ids: suggested_repo_ids,
        )

        repo_abilities.each do |ability|
          perms[ability.subject_id] =
            if ability.can?(:admin)
              :admin
            elsif ability.can?(:read)
              :read
            end
        end

        # override less permission or populate perms with :admin
        # for repos the user has admin on via repo owning org adminship
        Repository.accessible_via_org_admin(current_user, suggested_repo_ids).each do |repo_id|
          perms[repo_id] = :admin
        end

        perms
      end
  end

  def installations_suggestions_path
    urls.gh_app_installations_suggestions_path(integration, current_user, target_id: target.id)
  end

  def user_access_token_suggestions_path
    urls.user_access_token_suggestions_path(target_name: target.display_login, id: programmatic_access&.id)
  end
end
