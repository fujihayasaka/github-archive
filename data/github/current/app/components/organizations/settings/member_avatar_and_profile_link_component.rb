# typed: true
# frozen_string_literal: true

class Organizations::Settings::MemberAvatarAndProfileLinkComponent < ViewComponent::Base
  include AvatarHelper
  include ApplicationHelper

  attr_reader :user, :org, :show_admin_stuff

  def initialize(user:, org:, show_admin_stuff: false)
    @user = user
    @org = org
    @show_admin_stuff = show_admin_stuff
  end

  def profile_name_or_login
    user.profile_name.presence || user
  end

  def valid_user_with_profile_name?
    user.profile_name.present? && !user.suspended?
  end
end
