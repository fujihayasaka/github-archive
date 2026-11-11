# typed: true
# frozen_string_literal: true

class Orgs::MarketingController < ApplicationController
  before_action :redirect_to_org_new

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    render_404
  end

  private

  # Deprecating the Organization migration pages and functionality -
  # now just redirect the user to the new Organization page
  def redirect_to_org_new
    redirect_to new_organization_path
  end
end
