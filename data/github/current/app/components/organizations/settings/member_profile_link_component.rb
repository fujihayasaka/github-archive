# typed: true
# frozen_string_literal: true

class Organizations::Settings::MemberProfileLinkComponent < ViewComponent::Base
  attr_reader :user, :org, :show_admin_stuff

  def initialize(user:, org:, show_admin_stuff: false)
    @user = user
    @org = org
    @show_admin_stuff = show_admin_stuff
  end

  def profile_name_or_login
    user.display_name.presence || user
  end

  def valid_user_with_profile_name?
    user.display_name.present? && !user.suspended?
  end

  def member_url
    if show_admin_stuff
      org_person_path(org, user)
    else
      user_path(user)
    end
  end

  def show_membership_source?
    @show_admin_stuff
  end
end
