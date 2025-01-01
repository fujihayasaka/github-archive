# typed: true
# frozen_string_literal: true

class AdvancedSecurity::BusinessLevelUsageComponent < ApplicationComponent
  delegate :javascript_bundle, to: :helpers

  def initialize(business:, orgs_page:, users_page:)
    @business = business
    @orgs_page = orgs_page
    @users_page = users_page
  end

  def render?
    @business.advanced_security_purchased?
  end

  def show_ghas_usage_for_user_repos?
    return false if @users_page == -1
    AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business).feature_available_for_user_repositories?
  end
end
