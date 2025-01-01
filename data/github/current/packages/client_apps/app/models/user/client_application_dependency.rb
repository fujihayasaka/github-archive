# typed: true
# frozen_string_literal: true

module User::ClientApplicationDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { User }

  # Flag to know whether this user's using GitHub Desktop.
  def desktop_app_enabled?
    return unless id
    return @desktop_app_enabled if defined?(@desktop_app_enabled)

    @desktop_app_enabled = oauth_accesses
      .where(application_id: Apps::Privileged::Desktop.app_ids)
      .any?
  end

  def visual_studio_app_enabled?
    return unless id
    return @visual_studio_app_enabled if defined?(@visual_studio_app_enabled)

    @visual_studio_app_enabled = oauth_accesses
      .where(application_id: Apps::Privileged::Codespaces.visual_studio_app_ids)
      .any?
  end

  # Does this user have any of the native apps enabled?
  #
  # user - User
  #
  # Returns true if so, and false otherwise.
  def has_app_enabled?
    visual_studio_app_enabled? || desktop_app_enabled?
  end
end
