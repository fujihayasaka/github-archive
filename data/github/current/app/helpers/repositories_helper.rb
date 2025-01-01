# typed: false
# frozen_string_literal: true

module RepositoriesHelper
  include RichwebHelper
  include RepositoriesDefaultSelectionHelper
  include GitHub::Memoizer

  module CloneDownloadClick
    module FeatureClicked
      UNKNOWN = :UNKNOWN
      OPEN_IN_DESKTOP = :OPEN_IN_DESKTOP
      OPEN_IN_VISUAL_STUDIO = :OPEN_IN_VISUAL_STUDIO
      OPEN_IN_XCODE = :OPEN_IN_XCODE
      DOWNLOAD_ZIP = :DOWNLOAD_ZIP
      COPY_URL = :COPY_URL
      USE_SSH = :USE_SSH
      USE_HTTPS = :USE_HTTPS
      USE_GH_CLI = :USE_GH_CLI
      SHARE = :SHARE
      EMBED = :EMBED
    end
  end

  # How many stars a repo has to have before we show a message to the
  # owner suggesting they add a successor.

  STARGAZERS_THRESHOLD_FOR_SUCCESSOR_PROMPT = 1_000

  # Public: Get the URL to an image that should represent the given repository publicly.
  #
  # repo - a Repository
  # resource - a resource like a commit, pull request, issue
  #
  # Returns a String.
  def repository_open_graph_image_url(repo, resource: nil)
    if repo.public? && (custom_image = repo.open_graph_image)
      if resource && repo.show_enhanced_og_image?
        resource.og_image_url
      else
        custom_image.storage_external_url(current_user)
      end
    elsif repo.show_enhanced_og_image?
      (resource.presence || repo).og_image_url
    elsif repo.owner
      avatar_url_for(repo.owner, 400)
    else
      avatar_url_for(User.ghost, 400)
    end
  end

  def repository_adaptivecard_url(repo, resource: nil)
    return nil unless repo.public?
    return nil unless repo.feature_enabled?(:adaptivecards)
    (resource.presence || repo).og_image_url + "?type=adaptivecard"
  end

  # Public: Given a repository, determine if we should show a "generated from" link for that
  # repository that links back to the template from which it was cloned.
  #
  # repo - a Repository
  #
  # Returns a Boolean.
  def show_link_to_template_repository_for?(repo)
    return false unless template_repo = repo.template_repository
    return false if !logged_in? && !template_repo.public?

    template_repo.readable_by?(current_user)
  end

  # Public: Whether to show the "Use this template" button on a template repository,
  # so the viewer can clone the template to make a new repository.
  #
  # repo - the Repository being viewed
  #
  # Returns a Boolean.
  def show_use_this_template_button?(repo)
    repo.template? && logged_in?
  end

  def clone_template_repository_url(user, repository)
    owner = if repository.private? && repository&.owner&.organization?
      repository.owner
    end
    new_repository_path(owner: owner, template_owner: repository.owner, template_name: repository.name)
  end

  def default_branch_settings_url_for(repo_owner)
    if repo_owner == current_user
      settings_repositories_path
    elsif repo_owner.organization?
      settings_org_repo_defaults_path(repo_owner)
    end
  end

  def show_default_branch_settings_link_for?(repo_owner, org_adminable_by_current_user: nil)
    return true if logged_in? && repo_owner == current_user

    repo_owner.organization? && (!!org_adminable_by_current_user || repo_owner.adminable_by?(current_user))
  end

  LARGE_TWITTER_CARD_TYPE = "summary_large_image"
  SMALL_TWITTER_CARD_TYPE = "summary"

  # Public: Get the type of twitter:card that best suits the Open Graph image for the given
  # repository. See https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/summary
  #
  # repo - a Repository
  #
  # Returns a String.
  def repository_twitter_image_card(repo)
    if (repo.public? && repo.open_graph_image) || repo.show_enhanced_og_image?
      LARGE_TWITTER_CARD_TYPE
    else
      SMALL_TWITTER_CARD_TYPE
    end
  end

  # Public: Returns the String name of the currently selected language, properly capitalized.
  def get_selected_language(language)
    @all_language_names ||= Linguist::Language.all.map(&:name)
    index = @all_language_names.map(&:downcase).index(language)
    index ? @all_language_names[index] : "All"
  end

  def repo_meta_title
    return @full_title if @full_title.present?

    nwo = current_repository.name_with_display_owner
    return nwo if @page_title.blank?

    prefix = @page_title
    suffix = unless prefix.include?(nwo)
      " · #{nwo}"
    end
    "#{prefix}#{suffix}"
  end

  def repo_meta_description
    title = repo_meta_title
    description = current_repository.description

    # Some pages include the repo description in the title, so replace it with the repo name
    if title.present? && description.present? && title.to_s.include?(description)
      title = "#{current_repository.name_with_display_owner}"
    end

    meta_description = I18n.t("repos.meta_description", repo: current_repository.name_with_display_owner)
    opengraph_description(title&.to_s, description&.to_s, meta_description&.to_s)
  end

  # Determines whether the tree_name is:
  # - Branch
  # - Tag
  # - Undeterminable
  def tree_type
    return "branch" if qualified_tree_name.start_with?("refs/heads/")
    return "tag" if qualified_tree_name.start_with?("refs/tags/")
    "tree"
  end

  def clone_download_click_attributes(git_repo:, feature_clicked:)
    attrs = { feature_clicked: feature_clicked }

    if git_repo.is_a?(Repository)
      attrs[:git_repository_type] = :REPOSITORY
      attrs[:repository_id] = git_repo.id
    elsif git_repo.is_a?(Gist)
      attrs[:git_repository_type] = :GIST
      attrs[:gist_id] = git_repo.id
    end

    hydro_click_tracking_attributes("clone_or_download.click", attrs)
  end

  def open_in_desktop_tracking_attributes(git_repo)
    clone_download_click_attributes(
      git_repo: git_repo,
      feature_clicked: CloneDownloadClick::FeatureClicked::OPEN_IN_DESKTOP,
    )
  end

  def xcode_clone_button?
    logged_in? && current_repository.xcode_project?
  end

  def visual_studio_clone_button?
    logged_in? && current_user.visual_studio_app_enabled?
  end

  # Deprecated repository label helper previously used for GraphQL-backed objects.
  # Can be removed once remaining callers are migrated off of GraphQL.
  def deprecated_repository_label(is_archived:, is_template:, is_mirror:, visibility:, is_private:, is_stack_template:, classes: nil, tooltip: false)
    repo_type = RepositoriesTypeHelper.type(
      visibility: visibility,
      mirror: is_mirror,
      archived: is_archived,
      template: is_template,
    )
    if is_stack_template
      stack_label = repository_type_label_from("Stack", classes: classes)
    end
    tooltip_label = if tooltip
      repository_tooltip_from(is_archived: is_archived, is_private: is_private)
    end
    add_label_by_repo_type(repo_type, tooltip_label, stack_label, classes)
  end

  # Public: Get HTML to appropriately label the given ActiveRecord repository based on whether it's
  # private, a template, archived, internal, or a mirror.
  #
  # repo    - a Repository
  # classes - optional String of CSS classes to be used in addition to the normal label-styling CSS
  # tooltip - Boolean; indicates if a tooltip should be shown explaining what the label means
  #
  #  Returns HTML or nil.
  def repository_label(repo, classes: nil, tooltip: false)
    repo_type = RepositoriesTypeHelper.type(
      visibility: repo.visibility,
      mirror: repo.mirror?,
      archived: repo.archived?,
      template: repo.template?,
    )
    if show_stack_template_labels_icons?(repo)
      stack_label = repository_type_label_from("Stack", classes: classes)
    end
    tooltip_label = if tooltip
      repository_tooltip_from(is_archived: repo.archived?, is_private: repo.private?)
    end
    add_label_by_repo_type(repo_type, tooltip_label, stack_label, classes)
  end

  # Public: Get a tooltip message for describing a repository with the given traits.
  #
  # is_archived - Boolean; whether repository has been archived or not
  # is_private  - Boolean; whether repository is private
  #
  # Returns a String or nil.
  def repository_tooltip_from(is_archived:, is_private:)
    if is_archived
      "Read-only."
    elsif is_private
      "Only visible to its members."
    end
  end

  # Public: Get HTML to label the specified repository type.
  #
  # classes - extra CSS classes, optional; String
  # tooltip - an optional String tooltip to show on hover
  #
  # Returns a String of HTML or nil.
  def repository_type_label_from(repo_type, classes: nil, tooltip: nil)
    if repo_type.present?
      content_tag :span, repo_type, class: "Label #{repo_type == 'Public archive' ? 'Label--attention' : 'Label--secondary'} v-align-middle #{classes}", title: tooltip
    end
  end

  def repository_group_settings_label(repo)
    if repo&.access_group_setting
      content_tag :span, "Managed by group settings", class: "Label Label--secondary v-align-middle", title: "Managed by group settings"
    end
  end

  # used for handling manifest file paths
  # shown in files/_dependency_alert and network/dependencies

  def short_manifest_file_path(full_manifest_path)
    parts = full_manifest_path.split("/")
    short_path = parts.last(2).join("/")
    short_path.prepend("…/") if parts.count > 2
    short_path
  end

  def manifest_file_path_anchor(path)
    UrlHelper.escape_path(path)
  end

  def instrument_marketplace_quick_install_view(user, listings)
    GlobalInstrumenter.instrument("marketplace.new_repo_quick_install", {
      user:  current_user,
      action: :viewed,
      categorized_listings: {
        shown_listings: listings.keys
      },
    })
  end

  # Public: Should a permissions option be disabled?
  #         We use this to disable an option if a user's current permission is
  #         more capable than the option.
  #
  # current_permission_level - The Integer or Float permission rank.
  # button_action - The Symbol action name for a button.
  #
  # Returns a Boolean.
  def permissions_option_disabled?(current_permission_level, button_action)
    current_permission_level >= Ability::ACTION_RANKING[button_action]
  end

  # Public: Hide the used by section if the fragment has already been cached
  # as an empty html response, which means it has no package associations
  # i.e. the repository is not a package
  def hide_used_by_section?
    cached_fragment = read_fragment(used_by_sidebar_cache_key)
    !cached_fragment.nil? && cached_fragment.blank?
  end

  # Public: Show the billing warning for actions if the owner cannot access
  # actions for billing reasons
  #
  # owner - owner for the purposes of billing
  # current_user - the current user
  def render_actions_billing_warning_if_required(owner:, current_user:)
    if !Billing::ActionsPermission.new(owner).allowed?(public: current_repository.public?)
      render "repository_actions/billing_warning", view: create_view_model(
        RepositoryActions::BillingWarningView,
        owner: owner,
        current_user: current_user,
        current_repository: current_repository,
      )
    end
  end

  def show_security_features_notice_when_archiving(repository:)
    code_scanning = repository.code_scanning_enabled?
    if code_scanning
      yield code_scanning: code_scanning
    end
  end

  def show_security_features_notice_when_unarchiving(repository:)
    enable_advanced_security_on_state_change = repository.enable_advanced_security_on_state_change?

    code_scanning = (repository.public? && !GitHub.enterprise?) || enable_advanced_security_on_state_change # this also checks advanced security is purchased

    if code_scanning
      yield code_scanning: code_scanning
    end
  end

  def show_billing_notice_when_archiving?(repository:)
    GitHub.billing_enabled? &&
      repository.private? &&
      !repository.fork? &&
      !repository.part_of_unlimited_plan?
  end

  def sidebar_contributors_cache_key
    key = "sidebar:v3:contributors:list:#{current_repository.id}:#{current_repository.updated_at.to_i}#{GitHub.flipper[:contributors_testing_use_no_merges].enabled?(current_repository) ? ":use_no_merges" : ""}#{user_feature_enabled?(:contributors_testing_skip_bots) ? ":skip_bots" : ""}"
    return key unless GitHub.multi_tenant_enterprise?

    # We want to refresh the cache every 30 minutes
    time_key = Time.now.to_i / 30.minutes.to_i
    "#{key}:#{time_key}"
  end

  # Public indicates whether a prompt to add a successor should be shown
  #
  # repository: This is the repository being viewed
  #
  # Returns a Boolean
  def show_add_successor_prompt_for_popular_repos?(repository)
    return false if GitHub.enterprise?
    return false unless logged_in?
    return false unless repository.owner.user?
    return false unless repository.owner == current_user

    repository.stargazer_count > STARGAZERS_THRESHOLD_FOR_SUCCESSOR_PROMPT &&
        !current_user.dismissed_repository_notice?("popular_repo_successor_prompt", repository_id: repository.id) &&
        !current_user.has_successor?
  end

  # Should we include a hotkey shortcut to open the current page in github.dev?
  def include_github_dev_hotkey?
    return false if @github_dev_hotkey_already_rendered
    (
      github_dev_enabled?
    ).tap do |ret|
      if ret
        @github_dev_hotkey_already_rendered = true
      end
    end
  end

  def github_dev_enabled?
    GitHub.codespaces_serverless_editor_enabled? &&
    logged_in? &&
    Codespaces::LightweightWebEditor.can_handle_route?(
      controller_name: controller_name,
      action_name: action_name
    )
  end

  def codespace_keyboard_shortcut_path(repo, branch: nil, pull: nil)
    if pull.present?
      if pull.head_repository.present?
        # Even though we reference the PR through its base repo, we still require the head repo to exist for anything
        # else in codespaces to work. If the head repo is missing, we'll just fall back to the branch path instead
        new_with_pull_codespaces_path(pull.base_repository.owner, pull.base_repository, pull_id: pull.number, resume: 1)
      else
        new_with_branch_codespaces_path(repo.owner, repo, name: pull.head_ref_name, resume: 1)
      end
    elsif branch.present?
      new_with_branch_codespaces_path(repo.owner, repo, name: branch, resume: 1)
    else
      new_with_nwo_codespaces_path(repo.owner, repo, resume: 1)
    end
  end

  def add_label_by_repo_type(repo_type, tooltip_label, stack_label, classes)
    repo_type_label = repository_type_label_from(repo_type, classes: classes, tooltip: tooltip_label)
    labels = content_tag(:span, "")
    labels << stack_label unless stack_label.nil?
    labels << repo_type_label unless repo_type_label.nil?
    labels
  end

  def repo_non_transferrable_reason(repo)
    return if repo.can_transfer_ownership?
    return "Transfer this repository to another user or to an organization where you have the ability to create repositories." if repo.trade_controls_read_only?
    return "Internal repositories cannot be transferred." if repo.internal?

    "This repository is not transferrable. Please contact the owner of the root repository, #{repo.root.owner}."
  end
end
