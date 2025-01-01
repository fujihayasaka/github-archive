# typed: true
# frozen_string_literal: true

class Autocomplete::OrganizationsController < ApplicationController
  before_action :login_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:index]

  def index
    organizations = ::Organization.search(params[:q], limit: 10)
    visible_organizations = cap_filter.authorized_resources(organizations)
    respond_to do |format|
      format.html_fragment do
        render partial: "organizations/autocomplete", formats: :html, locals: {
          results: visible_organizations
        }
      end
      format.html do
        return head :not_acceptable unless request.xhr?
        render partial: "organizations/autocomplete", locals: {
          results: visible_organizations
        }
      end
    end
  end

  private

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
