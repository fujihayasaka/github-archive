# typed: true
# frozen_string_literal: true

class Blob::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include UrlHelper
  include AvatarHelper
  include StatusHelper
  include RepositoriesHelper
  include HydroHelper
  include BlobHelper
  include Repos::GitHubEnterpriseHelper

  attr_reader :repo, :tree_name, :commit, :blob, :path, :path_for_display, :short_path, :issue_template, :discussion_template,
    :valid_legacy_template, :is_workflow_file, :parsed_useragent,
    :last_commit_checks_status_summary, :last_commit_check_runs, :last_commit_checks_header_state

  YAML_FILES = /\A\.(yaml|yml)\z/
  ISSUE_TEMPLATE_DIRECTORY = ".github/ISSUE_TEMPLATE"
  ISSUE_TEMPLATE_CONFIG_PATH_REGEX = /\Aconfig\.(yaml|yml)\z/i

  # What kind of page title should we show? I guess some blobs don't have
  # names (but why?).
  #
  # Returns a String.
  def page_title
    if blob.name.blank?
      "#{repo.name_with_display_owner} at #{h tree_name_for_display}"
    else
      "#{repo.name}/#{path_for_display} at #{tree_name_for_display} · #{repo.name_with_display_owner}"
    end
  end

  # The last commit to touch the blob.
  def last_commit
    return @last_commit if defined?(@last_commit)

    last_contribution = contributors.first
    @last_commit      = last_contribution && @repo.commits.find(last_contribution["commit"])
  end

  # How many people have contributed to this file? We're cheating here
  # because sometimes a User will commit with multiple email addresses. So
  # we use the User count if we're showing them all, otherwise we use the
  # email count.
  #
  # Returns an Integer of contributors.
  def contributor_count
    contributor_users.size > 26 ? contributor_emails.size : contributor_users.size
  end

  # How many contributors that aren't Users?
  #
  # Returns an Integer.
  def other_contributors_count
    contributor_count - contributor_users.size
  end

  # Users attributed to blob_contributors' emails, sorted by number of
  # contributions.
  #
  # Returns an Array of Users.
  def contributor_users
    @contributor_users ||= contributor_users!
  end

  def contributor_users!
    commit_count_by_email = Hash[contributors.map { |c| [c["author"].downcase, c["count"]] }]
    users = {}

    business = repo.enterprise_managed_business if repo.is_enterprise_managed?
    User.find_by_emails(contributor_emails, business: business).each do |email, user|
      # It's possible that we can get a user with an email address
      # that does not match any of the email addresses from GitRPC
      # due MySQL collation matching and returning users for email
      # addresses that are slightly different than the address we
      # queried for.
      #
      # For example, querying for
      #   aurélien.alriquet@devinci.fr
      # can return a user with an email address of
      #   aurelien.alriquet@devinci.fr
      #
      # but the strings will not match in Ruby.
      #
      # I think these are actually different email addresses
      # in practice, so this kind of "fuzzy" match probably
      # shouldn't result in the user being displayed as a
      # blob contributor, even though they may very well
      # be the same person.
      #
      if user && (count = commit_count_by_email[email.downcase])
        users[user] ||= 0
        users[user] += count
      end
    end

    users.keys.sort_by { |user| users[user] }.reverse
  end

  def contributor_emails
    @contributor_emails ||= contributors.map { |c| c["author"] }
  end

  # Did backend time out and gave partial contributor data?
  def contributors_is_truncated?
    raw_contributors["truncated"]
  end

  # The tooltip we present to users when the edit action is displayed.
  #
  # action - operation to construct a tooltip for (either :edit, or :delete).
  #
  # Returns a String
  def file_action_tooltip(action:)
    raise(ArgumentError, "action must be :edit or :delete") unless [:edit, :delete].include?(action)

    if edit_enabled?
      if can_push?
        "#{action.to_s.capitalize} this file"
      elsif has_fork?
        "#{action.to_s.capitalize} the file in your fork of this project"
      elsif can_fork?
        "Fork this repository and #{action} the file"
      end
    elsif logged_in?
      if !branch?
        "You must be on a branch to make or propose changes to this file"
      elsif T.must(current_user).must_verify_email?
        "You need to verify your email address to propose changes"
      elsif can_fork? && restrict_create_repositories_in_personal_namespace?(current_user)
        "You must be able to create repositories in your personal namespace to propose changes this way"
      else
        "You must be able to fork a repository to propose changes"
      end
    else
      "You must be signed in to make or propose changes"
    end
  end

  # Whether this blob refers to a branch.
  #
  # Returns a Boolean.
  def branch?
    repo.heads.exist?(tree_name)
  end

  # Whether this blob is on the default branch.
  #
  # Returns a Boolean.
  def default_branch?
    tree_name == repo.default_branch
  end

  # Should the edit action be displayed in an enabled state?
  def edit_enabled?
    return false if repo.locked_on_migration?
    return false unless logged_in? && branch?
    return false if T.must(current_user).must_verify_email?
    # Auto-forks are always to a personal namespace, so restrict edit if a fork is needed and that setting is enabled
    can_push? || has_fork? || (can_fork? && !restrict_create_repositories_in_personal_namespace?(current_user))
  end

  def can_push?
    return false unless logged_in?

    repo.pushable_by?(current_user, ref: branch? ? tree_name : nil)
  end

  def has_fork?
    return false unless logged_in?
    return false if repo.archived? && current_user == repo.owner
    repo.network_has_fork_for?(current_user)
  end

  def can_fork?
    logged_in? && T.must(current_user).can_fork?(repo)
  end

  # Should the blob appear "rendered"? i.e. Using render to display .geojson file
  # as visual map. Even if the blob *can* be rendered, the user may have selected
  # the "source" view, in which case we should *not* `use_render?`.
  def use_render?
    if blob.render_file_type_for_display(:view)
      !source_selected?
    else
      false
    end
  end

  # Should the blob appear "rendered"? i.e. Using viewscreen to display .geojson file
  # as visual map. Even if the blob *can* be rendered, the user may have selected
  # the "source" view, in which case we should *not* `use_viewscreen?`.
  def display_with_code_rendering_service?
    if code_rendering_service&.supports_view?
      !source_selected?
    else
      false
    end
  end

  def code_rendering_service
    return nil unless blob
    @code_rendering_service ||= CodeRenderingService.for(blob, :view, current_user, nil, opts: { parsed_useragent: parsed_useragent })
  end

  # Determine the current state of the render toggle.
  def toggle_state
    short_path == blob_short_path(blob) ? :source : :rendered
  end

  # Is the "source" option of the render toggle selected?
  def source_selected?
    toggle_state == :source
  end

  # Is the "rendered" option of the render toggle selected?
  def rendered_selected?
    toggle_state == :rendered
  end

  def show_invalid_citation_warning?
    return false unless logged_in?
    return false unless repo.pushable_by?(current_user)
    preferred_citation = repo.preferred_citation(tree_name: tree_name)
    return false unless preferred_citation&.path == path
    return false if preferred_citation.valid_but_unparsable_citation_file?

    Repositories::Citation.exists?(repo, tree_name: tree_name) && !Repositories::Citation.from_repository(repo, tree_name: tree_name).valid?
  end

  def show_license_meta?
    return false if repo.license.nil? || repo.license.pseudo_license?
    preferred_license = repo.preferred_license
    preferred_license && preferred_license.path == path
  end

  def overriding_global_funding_file?
    path.downcase.include?(FundingLinks::FILENAME.downcase) && repo.overriding_global_funding_file?
  end

  def show_dependabot_configuration_banner?
    return false unless repo.automated_dependency_updates_visible_to?(current_user)

    dependabot_config_file?
  end

  def dependabot_config_file_path
    path if dependabot_config_file?
  end

  def dependabot_config_file?
    return @dependabot_config_file if defined? @dependabot_config_file
    @dependabot_config_file = ::Dependabot.recognized_config_path?(path: path.downcase)
  end

  def release_count
    return @release_count if defined?(@release_count)
    @release_count = Releases::Public.published_release_count_for_repository(repo.id)
  end

  def stack_banner_heading
    "Publish this stack as a release"
  end

  def stack_banner_info
    if repo.public?
      "Make your stack discoverable in releases and the GitHub Marketplace. People will use it to create new repositories."
    else
      "Make your stack discoverable in releases. People with access will use it to create new repositories."
    end
  end

  def show_publish_action_banner?
    return false unless logged_in?
    return false if GitHub.enterprise?
    return false if T.must(current_user).dismissed_notice?(UserNotice::PUBLISH_ACTION_FROM_DOCKERFILE_NOTICE)
    return false unless repo.pushable_by?(current_user)
    return false unless repo.listable_action?
    return false if repo.listed_action
    return false unless path == repo.action_at_root&.path

    true
  end

  def show_publish_stack_banner?
    false
  end

  def rich_form_message(message)
    GitHub::Goomba::IssueFormTemplatesErrorMessagePipeline.to_html(message, {})
  end

  def filename
    blob.name
  end

  def is_yaml_file?
    ext = File.extname(path)
    ext =~ YAML_FILES
  end

  def is_yaml_path?
    return false unless path.starts_with?(ISSUE_TEMPLATE_DIRECTORY)

    is_yaml_file? && File.basename(path) !~ ISSUE_TEMPLATE_CONFIG_PATH_REGEX
  end

  def is_discussions_yaml_path?
    return false unless path.starts_with?(DiscussionTemplates::TEMPLATES_DIRECTORY)

    is_yaml_file?
  end

  def lab_workflow_file?
    is_workflow_file && path&.split("/")&.second == "workflows-lab"
  end

  def initialize_commit_checks_status(combined_status_view)
    combined_status = combined_status_view.sorted_statuses
    @last_commit_checks_status_summary = combined_status_view.checks_status_summary

    if combined_status_view.all_succeeded?
      @last_commit_checks_header_state = "SUCCEEDED"
    elsif combined_status_view.all_failing?
      @last_commit_checks_header_state = "FAILED"
    elsif combined_status_view.pending?
      @last_commit_checks_header_state = "PENDING"
    else
      @last_commit_checks_header_state = "UNSUCCESSFUL"
    end

    @last_commit_check_runs = []

    combined_status.each do |status|
      if status.application
        avatar_url = status.application.url
        avatar_description = "#{status.application.name} (@#{status.application.user.display_login}) generated this status."
        avatar_logo = status.application.preferred_avatar_url
        avatar_background_color = "##{status.application.preferred_bgcolor}"
      elsif status.creator
        avatar_url = user_path(status.creator)
        avatar_description = "@#{status.creator.display_login.chomp('[bot]')} generated this status."
        avatar_logo = avatar_url_for status.creator
        avatar_background_color = "#ffffff"
      end

      check_run = {}.tap do |opts|
        opts[:state]              = status.state
        opts[:description]        = status.description || default_status_check_description(status.state)
        opts[:target_url]         = status.target_url
        opts[:name]               = status.contextual_name
        opts[:icon]               = icon_symbol_for_state(status.state)
        opts[:avatar_url]         = avatar_url
        opts[:avatar_description] = avatar_description
        opts[:avatar_logo]        = avatar_logo
        opts[:avatar_background_color] = avatar_background_color
        opts[:additional_context] = additional_status_check_context(status.state, status.duration_in_seconds)
        opts[:pending]            = status_check_pending?(status.state)
      end

      @last_commit_check_runs << check_run
    end
  end

  def last_commit_primary_author
    last_commit_authors = []
    authors = last_commit.async_unique_visible_author_actors(current_user).sync
    primary_author = authors.first

    {
      login: primary_author.async_visible_user(current_user).sync&.display_login,
      display_name: primary_author.display_name,
      avatar_url: primary_author.async_actor.sync&.primary_avatar_url || User::AvatarList.default_image_url("gravatar-user-420")
    }
  end

  def dropdown_tracking_attributes(small_screen: false, github_dev_enabled:)
    {
      type: "blob_edit_dropdown.more_options_click",
      context: {
        repository_id: repo.id,
        actor_id: current_user&.id,
        github_dev_enabled: github_dev_enabled,
        edit_enabled: edit_enabled?,
        small_screen: small_screen
      }
    }.to_json
  end

  def github_dev_link_tracking_attributes(small_screen: false)
    {
      type: "blob_edit_dropdown.dev_link_click",
      context: {
        repository_id: repo.id,
        actor_id: current_user&.id,
        edit_enabled: edit_enabled?,
        small_screen: small_screen
      }
    }.to_json
  end

  private

  # The authors who have modified the current blob
  #
  # Returns an array of hashes, one per author who touched the blob.
  # Each hash has 'author' email, last 'commit' oid by that author, and
  # 'count' of total commits by that author
  def contributors
    raw_contributors["data"]
  end

  def raw_contributors
    @raw_contributors ||= repo.rpc.read_blob_contributors(
      commit.oid,
      blob.path,
      co_authors: true, # TODO: remove this option; coauthors are always there now
    )
  end
end
