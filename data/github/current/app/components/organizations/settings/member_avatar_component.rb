# typed: true
# frozen_string_literal: true

class Organizations::Settings::MemberAvatarComponent < ViewComponent::Base
  attr_reader :user, :org, :show_admin_stuff

  def initialize(user:, org:, show_admin_stuff: false)
    @user = user
    @org = org
    @show_admin_stuff = show_admin_stuff
  end

  def member_url
    if show_admin_stuff
      org_person_path(org, user)
    else
      user_path(user)
    end
  end
end
