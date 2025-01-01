# typed: true
# frozen_string_literal: true

class Orgs::AccessListMembersController < ApplicationController
  include OrganizationsHelper
  include OrganizationsControllerMethods
  include SignupHelper

  before_action :login_required
  before_action :require_xhr
  before_action :sudo_filter
  after_action :customer_category_instrumentation

  javascript_bundle "signup"
  javascript_bundle "organizations"
  stylesheet_bundle :signup

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    only: [:index]

  # Builds HTML for the org invite and user to org transform pages' js.
  def index
    user = User.find_by(login: params[:member])

    if user
      respond_to do |format|
        format.html do
          render partial: "organizations/transform/access_list_member", locals: { user: user }
        end
      end
    else
      head :not_found
    end
  end
end
