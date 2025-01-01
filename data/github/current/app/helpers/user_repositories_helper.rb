# typed: false
# frozen_string_literal: true

module UserRepositoriesHelper
  include FeatureFlagHelper
  include ActionView::Helpers::UrlHelper

  # Public: Build a page title for a user repositories page
  #
  # login: String login of the user
  # name: String profile name of the user
  # is_viewer: Boolean indicating whether the viewer is the user
  #
  # Returns a String
  def user_repositories_title(login:, name:, is_viewer:)
    return "Repositories" if login.nil?

    if is_viewer
      "Your Repositories"
    else
      profile_page_title(login: login, name: name, section: "Repositories")
    end
  end

  def show_owner_prefix?(owner:, owner_id:)
    return false unless owner.is_a?(PlatformTypes::Organization)
    owner_id != this_user.id
  end

  def user_repositories_class_names(is_private:, is_fork:, is_mirror:, is_archived:)
    class_names = []
    class_names << (is_private ? "private" : "public")
    class_names << (is_fork ? "fork" : "source")
    class_names << "mirror" if is_mirror
    class_names << "archived" if is_archived
    class_names.join(" ")
  end

  def user_repositories_type(visibility:, is_mirror:, is_archived:, is_template:)
    RepositoriesTypeHelper.type(
      visibility: visibility,
      mirror: is_mirror,
      archived: is_archived,
      template: is_template,
    )
  end

  def user_repositories_filtering?(phrase:, language:, type_filter:)
    phrase.present? || language.present? || type_filter.present?
  end

  # Public: Returns a string for use in a phrase like "for X repositories".
  def type_filter_description(type)
    type == "fork" ? "forked" : type
  end

  # Public: Returns a pretty name for the current filter, e.g., "Forks" for the filter "fork".
  def selected_type_filter(type:, types:)
    types[type] || "All"
  end

  def user_repositories_valid_type_filters(include_private:, include_public: true, include_archived: true)
    filters = { "" => "All" }

    if include_private
      filters["public"] = "Public"
      filters["private"] = "Private"
    end

    filters = filters.merge(
      "source" => "Sources",
      "fork"   => "Forks",
    )

    if include_archived
      filters["archived"] = "Archived"
    end

    filters["sponsorable"] = "Can be sponsored" if GitHub.sponsors_enabled?
    filters["mirror"] = "Mirrors" if GitHub.mirrors_enabled?
    filters.delete("public") unless GitHub.public_repositories_available? && !include_public

    filters["template"] = "Templates"

    filters
  end

  def viewable_repositories_owned_by
    Repositories.domain.recent_by_owner_for_actor(owner_id: this_user.id)
  end
end
