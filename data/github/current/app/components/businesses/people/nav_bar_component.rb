# typed: true
# frozen_string_literal: true

class Businesses::People::NavBarComponent < ApplicationComponent
  PAGES = [
    :organizations,
    :teams,
    :enterprise_installations
  ]

  def initialize(
    business:,
    business_user_account:,
    user: nil,
    placeholder_text:,
    page: :organizations
  )
    @business = business
    @business_user_account = business_user_account
    @user = user || business_user_account&.user
    @placeholder_text = placeholder_text
    @page = page
  end

  private

  def render?
    return @business.present? && @user.present? && PAGES.include?(@page) if GitHub.enterprise?
    @business.present? && @business_user_account.present? && PAGES.include?(@page)
  end

  def organizations_path
    return organizations_enterprise_user_account_path(@business_user_account) if @user.nil?
    enterprise_person_organizations_enterprise_path(@business, @user)
  end

  def teams_path
    return nil if @user.nil?
    enterprise_person_teams_enterprise_path(@business, @user)
  end

  def enterprise_installations_path
    return enterprise_installations_enterprise_user_account_path(@business_user_account) if @user.nil?
    enterprise_person_enterprise_installations_enterprise_path(@business, @user)
  end

  def search_path
    case @page
    when :organizations
      organizations_path
    when :teams
      teams_path
    when :enterprise_installations
      enterprise_installations_path
    end
  end

  def search_container_name
    case @page
    when :organizations
      "organizations-list"
    when :teams
      "teams-list"
    when :enterprise_installations
      "installations-list"
    end
  end

  def render_cloud_server_toggle?
    return false if GitHub.single_business_environment?
    # this selector does not apply to teams, don't render it if we are viewing teams
    return false if teams_path.present? && link_selected?(teams_path)

    true
  end
end
