# typed: true
# frozen_string_literal: true

module User::ClientApplicationDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { User }

  # Flag to know whether this user's using GitHub Desktop TNG.
  def desktop_app_enabled?
    return unless id
    return @desktop_app_enabled if defined?(@desktop_app_enabled)

    @desktop_app_enabled = ClientApplicationSet.new(id).include?(:github_desktop)
  end

  def enable_desktop_app(platform)
    return unless id
    @desktop_app_enabled = true

    if ClientApplicationSet.new(id).add(:github_desktop)
      GitHub.dogstats.increment("desktop.install")
    end

    if platform == :mac
      Interaction.track_desktop_mac(self)
    elsif platform == :windows
      Interaction.track_desktop_windows(self)
    end
  end

  def visual_studio_app_enabled?
    return unless id
    return @visual_studio_app_enabled if defined?(@visual_studio_app_enabled)

    @visual_studio_app_enabled =
      ClientApplicationSet.new(id).include?(:github_for_visual_studio)
  end

  def enable_visual_studio_app
    return unless id
    @visual_studio_app_enabled = true

    if ClientApplicationSet.new(id).add(:github_for_visual_studio)
      GitHub.dogstats.increment("app", tags: ["action:install", "type:visualstudio"])
    end
  end

  def xcode_app_enabled?
    return unless id
    return @xcode_app_enabled if defined?(@xcode_app_enabled)
    @xcode_app_enabled = ClientApplicationSet.new(id).include?(:xcode)
  end

  def enable_xcode_app
    return unless id
    @xcode_app_enabled = true
    if ClientApplicationSet.new(id).add(:xcode)
      GitHub.dogstats.increment("xcode.install")
      GitHub.dogstats.increment("app", tags: ["action:install", "type:xcode"])
    end
  end

  # Does this user have any of the native apps enabled?
  #
  # user - User
  #
  # Returns true if so, and false otherwise.
  def has_app_enabled?
    visual_studio_app_enabled? || desktop_app_enabled? || xcode_app_enabled?
  end
end
