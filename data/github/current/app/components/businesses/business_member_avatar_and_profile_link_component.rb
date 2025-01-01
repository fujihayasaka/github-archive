# typed: true
# frozen_string_literal: true

class Businesses::BusinessMemberAvatarAndProfileLinkComponent < ViewComponent::Base

  attr_reader :user, :business

  def initialize(user:, business:)
    @user = user
    @business = business
  end

  def profile_name_or_login
    user.profile_name.presence || user
  end

  def valid_user_with_profile_name?
    user.profile_name.present? && !user.suspended?
  end

  def member_url
    enterprise_person_organizations_enterprise_path(@business, @user)
  end
end
