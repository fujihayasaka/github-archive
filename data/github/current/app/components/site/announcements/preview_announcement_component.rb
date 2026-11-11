# typed: true
# frozen_string_literal: true

class Site::Announcements::PreviewAnnouncementComponent < ApplicationComponent
  delegate :avatar_for, :github_simplified_markdown, to: :helpers

  def initialize(announcement, user_dismissible, owner)
    @announcement = announcement
    @user_dismissible = user_dismissible
    @owner = owner
  end

  def banners
    banners = EnterpriseBanner.active.where(owner: banner_levels_to_display.compact)

    sorted_banners = []

    # Sort banners so repo is always first, then org, then enterprise
    sorted_banners += banner_of_type(banners, Repository)
    sorted_banners += banner_of_type(banners, Organization)
    sorted_banners += banner_of_type(banners, Business)

    sorted_banners
  end

  def banner_of_type(banners, type)
    if existing_banner = banners.find { |sb| sb.owner.instance_of?(type) }
      [from_banner(existing_banner)]
    elsif owner.instance_of?(type)
      [{ text: github_simplified_markdown(announcement), dismissible: user_dismissible, owner: owner, date: Time.new }]
    else
      []
    end
  end

  def from_banner(banner)
    if banner.owner == owner
      { text: github_simplified_markdown(announcement), dismissible: user_dismissible, owner: owner, date: Time.new }
    else
      { text: github_simplified_markdown(banner.message), dismissible: banner.dismissible, owner: banner.owner, date: banner.updated_at }
    end
  end

  attr_reader :announcement, :user_dismissible, :owner

  private

  def banner_levels_to_display
    case owner
    when Business
      [owner]
    when Organization
      [owner, owner.business]
    when Repository
      [owner.owner&.business, owner.owner, owner]
    end
  end
end
