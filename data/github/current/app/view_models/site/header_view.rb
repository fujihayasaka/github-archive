# typed: true
# frozen_string_literal: true

class Site::HeaderView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include ResilienceHelper
  include ActionView::Helpers::CaptureHelper
  include GitHub::Memoizer
  include Search::Blackbird::Features

  attr_reader :current_organization
  attr_reader :current_repository
  attr_reader :is_mobile_request
  attr_reader :params
  attr_reader :current_copilot_user
  attr_reader :response

  def current_copilot_user_v2
    current_copilot_user
  end

  # Public: Get the search path.
  #
  # Returns a string.
  def search_path
    scoped_search_path || unscoped_search_path
  end

  # Public: Get the search path for the current scope.
  #
  # Returns a string.
  def scoped_search_path
    case scope
    when Repository
      urls.repo_search_path(current_repository.owner, current_repository)
    when Organization
      urls.org_search_path(current_organization)
    when User
      urls.user_search_path(currently_viewed_user)
    when Topic
      "/topics/#{current_topic.name}"
    else
      nil
    end
  end

  # Public: Get the search path for the owner of the current repository scope.
  #
  # Returns a string.
  def owner_scoped_search_path
    return nil unless scope.is_a? Repository
    case scope.owner
    when Organization
      urls.org_search_path(scope.owner)
    when User
      urls.user_search_path(scope.owner)
    else
      nil
    end
  end

  # Public: Get the unscoped search path.
  #
  # Returns a string.
  def unscoped_search_path
    urls.search_path
  end

  # Public: Get the unscoped dotcom search path used by unified search on Enterprise.
  #
  # Returns a string.
  def unscoped_dotcom_search_path
    return unless GitHub.enterprise?

    urls.dotcom_search_path
  end

  def query
    case params[:q]
    when Array;  params[:q].join(" ")
    when String; params[:q]
    end
  end

  # Public: Get the text to show in the search scope badge.
  #
  # Returns a string.
  def search_scope_badge_text
    case scope
    when Repository
      "This repository"
    when Organization
      "This organization"
    when User
      "This user"
    when Topic
      "This topic"
    end
  end

  # Public: Get the text to show in the jump to suggestion search scope badge.
  #
  # Returns a string.
  def jump_to_search_scope_badge_text
    case scope
    when Repository
      "In this repository"
    when Organization
      "In this organization"
    when User
      "In this user"
    when Topic
      "In this topic"
    else
      "Search"
    end
  end

  # Public: Get the text to show in the jump to suggestion search owner scope badge.
  #
  # Returns a string.
  def jump_to_search_owner_scope_badge_text
    return "Search" unless scope.is_a? Repository
    return "In this organization" if current_repository.owner.organization?
    "In this user"
  end

  def jump_to_search_scope_badge_aria_label
    badge_text = jump_to_search_scope_badge_text
    return jump_to_search_scope_badge_aria_label_global if badge_text == "Search"

    # downcase first letter so it makes sense to screenreader
    badge_text[0].downcase + badge_text[1..-1]
  end

  def jump_to_search_owner_scope_badge_aria_label
    badge_text = jump_to_search_owner_scope_badge_text
    return jump_to_search_scope_badge_aria_label_global if badge_text == "Search"

    # downcase first letter so it makes sense to screenreader
    badge_text[0].downcase + badge_text[1..-1]
  end

  def jump_to_search_scope_badge_aria_label_global
    "in all of #{GitHub.search_flavor}"
  end

  # Public: Get the text to show in the jump to suggestion global search badge.
  #
  # Returns a String.
  def jump_to_search_global_badge_text
    "All #{GitHub.search_flavor}"
  end

  # Public: Get the text to use for the search's aria label.
  #
  # Returns a string.
  def search_aria_label_text
    case scope
    when Repository
      "Search this repository"
    when Organization
      "Search this organization"
    when User
      "Search this user"
    when Topic
      "Search this topic"
    else
      "Search #{GitHub.search_flavor} or jump to"
    end
  end

  # Public: Is the search bar in the header view scoped?
  #
  # Returns a boolean.
  def search_scoped?
    scope.present?
  end

  # Public: Placeholder text for the search box.
  #
  # Returns a String.
  def search_placeholder_text
    if search_scoped?
      scoped_search_placeholder_text
    else
      unscoped_search_placeholder_text
    end
  end

  # Public: Placeholder text for the search box that will perform a scoped search.
  def scoped_search_placeholder_text
    current_user ? "Search or jump to…" : "Search"
  end

  # Public: Placeholder text for the search box that will perform an unscoped search.
  def unscoped_search_placeholder_text
    current_user ? "Search or jump to…" : "Search #{GitHub.search_flavor}"
  end

  def current_topic
    return unless params

    if topic_name = params[:topic_name]
      @current_topic ||= Topic.find_by_name(topic_name)
    end
  end

  # Returns the user being viewed (if any).
  def currently_viewed_user
    return unless params

    return @currently_viewed_user if defined?(@currently_viewed_user)

    @currently_viewed_user ||= begin
      if id = params[:user_id] || params[:user] || params[:id]
        User.find_by(login: id.to_s, type: "User")
      end
    end
  end

  def include_repository_scope?
    response.nil? || response.status < 400
  end

  def include_owner_scope?(viewer:)
    return false unless currently_viewed_user.present?
    return false if currently_viewed_user.hide_from_user?(viewer)
    return false if currently_viewed_user.is_enterprise_managed? && currently_viewed_user != viewer
    true
  end

  def scope
    # Prefer repository over organization if both are present
    if current_repository.present? && current_repository.persisted? && include_repository_scope?
      current_repository
    elsif current_organization.present? && current_organization.persisted?
      current_organization
    elsif currently_viewed_user.present? && currently_viewed_user.persisted?
      currently_viewed_user
    elsif current_topic.present?
      current_topic
    end
  end

  def use_blackbird_monolith_integration?
    blackbird_enabled?
  end

  def has_navigation_repository?
    current_user&.has_navigation_repository?
  end

  memoize def copilot_natural_language_github_search_enabled?
    with_database_error_fallback(fallback: false) { logged_in? && current_user&.feature_flag_enabled_or_raise?(:copilot_natural_language_github_search) } # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  private

  def default_result_type
    case scope
    when Repository
      "Code"
    else
      "All"
    end
  end
end
