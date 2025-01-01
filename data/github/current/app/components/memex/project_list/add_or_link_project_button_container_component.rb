# typed: true
# frozen_string_literal: true

class Memex::ProjectList::AddOrLinkProjectButtonContainerComponent < ApplicationComponent
  attr_reader :owner, :team, :context, :multiselect, :label

  sig { returns(T.nilable(MemexStats::UIValues)) }
  attr_reader :ui

  renders_one :link_interstitial, -> (scheme:, &block) do
    @link_interstitial_scheme = scheme
    Primer::Beta::Text.new(tag: :p) { block.call }
  end

  renders_one :unlink_interstitial, -> (scheme:, &block) do
    @unlink_interstitial_scheme = scheme
    Primer::Beta::Text.new(tag: :p) { block.call }
  end

  # multiselect: - Can the user select multiple projects at once.
  # is_template: - Determine if we are linking MemexProjects that are a template.
  sig do
    params(
      context: T.any(T.class_of(Repository), T.class_of(Team), T.class_of(Organization)),
      owner: T.any(Organization, User),
      team: T.untyped, # todo: add more specific type here
      multiselect: T::Boolean,
      tooltip: String,
      is_template: T::Boolean,
      ui: T.nilable(MemexStats::UIValues),
    ).void
  end
  def initialize(context:, owner:, team: nil, multiselect: true, tooltip: "", is_template: false, ui: nil)
    @context = context
    @team = team
    @owner = owner
    @multiselect = multiselect
    @tooltip = tooltip
    @is_template = is_template
    @label = is_template ? "template" : "project"
    @ui = ui
  end

  def is_template?
    @is_template
  end

  # The MemexProject model used to populate the form attributes used to create a new MemexProject.
  def new_memex_project_record
    title = if is_template?
      MemexProject.default_user_template_title(current_user)
    else
      MemexProject.default_user_title(current_user)
    end

    MemexProject.new(
      title: title,
    )
  end

  def render?
    current_user_can_push? || current_user_is_team_admin_or_team_org_member?
  end

  memoize def upsert_path
    if @context == Repository
      upsert_repo_project_beta_path(owner, current_repository)
    elsif @context == Team
      upsert_team_project_beta_path(owner, team)
    end
  end

  memoize def projects_path
    if owner.organization?
      org_projects_path(owner.display_login)
    else
      user_projects_path(owner.display_login)
    end
  end

  memoize def suggestions_path
    if @context == Repository
      repo_project_beta_suggestions_path(owner, current_repository, filter: is_template? ? "templates" : nil)
    elsif @context == Team
      team_project_beta_suggestions_path(owner, team, filter: is_template? ? "templates" : nil)
    end
  end

  memoize def suggestions_recent_path
    if @context == Repository
      repo_project_beta_suggestions_path(owner, current_repository, scope: "recent", filter: is_template? ? "templates" : nil)
    elsif @context == Team
      team_project_beta_suggestions_path(owner, team, scope: "recent", filter: is_template? ? "templates" : nil)
    end
  end

  memoize def footer_text
    if owner.organization?
      "Go to the #{owner.display_login} organization to create a new #{label}"
    else
      "Go to your profile to create a new #{label}"
    end
  end

  memoize def current_user_can_push?
    return false if @context != Repository
    helpers.current_user_can_push?
  end

  memoize def repo_org_member_or_owner?
    return true unless @context == Repository
    if owner.organization?
      owner.direct_or_team_member?(current_user)
    else
      owner == current_user
    end
  end

  memoize def current_user_is_team_admin_or_team_org_member?
    return false if @context != Team
    return true if @team.adminable_by?(current_user)
    @team.member?(current_user) && @team.organization.member?(current_user)
  end
end
