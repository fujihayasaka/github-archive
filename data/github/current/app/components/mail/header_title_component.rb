# typed: true
# frozen_string_literal: true

# Creates a centered icon + title for emails. Useful at the top of your email.
class Mail::HeaderTitleComponent < ApplicationComponent
  attr_reader :classes, :title, :icon_url, :avatar, :avatar_plus_avatar

  # See /public/images/email/icon for available icons. Or add your new icon there.
  #
  # We recommend using icons from: https://ghicons.github.com/
  #
  # title - String representing the title
  # icon - String representing the name of an icon file
  # avatar - Object that can have an avatar image path resolved (e.g. User)
  # avatar_plus_avatar - Array of 2 Objects, each of which can have an avatar image path resolved
  # classes - String of CSS classes to apply to the component
  def initialize(title:, icon: nil, avatar: nil, avatar_plus_avatar: nil, classes: nil)
    @classes = class_names("btn", classes)
    @title = title
    @avatar = avatar
    @avatar_plus_avatar = avatar_plus_avatar

    if !@avatar_plus_avatar.nil? && @avatar_plus_avatar.size != 2
      raise ArgumentError, "avatar_plus_avatar must be an Array containing two elements if provided"
    end

    if icon
      @icon_url  = image_url(icon)
    end
  end

  private

  def image_url(icon)
    mailer_static_asset_path("/images/email/icons/#{icon}")
  end
end
