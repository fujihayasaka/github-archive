# typed: true
# frozen_string_literal: true

class Orgs::AccessListMembersController < ApplicationController
  include OrganizationsHelper
  include OrganizationsControllerMethods
  include SignupHelper

  before_action :login_required
  before_action :require_xhr
  after_action :customer_category_instrumentation

  javascript_bundle "signup"
  javascript_bundle "organizations"
  stylesheet_bundle :signup

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    only: [:index]

  # Builds HTML for the org invite and user to org transform pages' js.
  def index
    user = User.find_by(login: params[:member])

    if user
      respond_to do |format|
        format.html do
          if params[:new_org_transform].present?
            render partial: "organizations/transform/org_owner_item", locals: {
              user: user,
              full_name: user.billing_contact.fullname.presence || user.profile_name,
              hide_remove_button: params[:hide_remove_button] == "true",
            }
          else
            render partial: "organizations/transform/access_list_member", locals: { user: user }
          end
        end
      end
    else
      head :not_found
    end
  end
end
