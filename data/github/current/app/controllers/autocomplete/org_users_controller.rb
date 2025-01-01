# typed: true
# frozen_string_literal: true

class Autocomplete::OrgUsersController < ApplicationController
  before_action :login_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    return render_404 unless current_organization

    respond_to do |format|
      view = create_view_model(AutocompleteView, { query: params[:q], organization: current_organization, org_members_only: true })
      format.html_fragment do
        render partial: "users/autocomplete", formats: :html, locals: {
          view: view,
          suggestions: view.suggestions
        }
      end
      format.html do
        return head :not_acceptable unless request.xhr?
        render partial: "users/autocomplete", locals: {
          view: view,
          suggestions: view.suggestions
        }
      end
    end
  end

  private

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def current_organization
    helpers.current_organization || (
      if id = helpers.org_login_param || params[:id]
        if logged_in?
          org = Organization.find_by_login(id)
          return org if org && org.user_is_outside_collaborator?(current_user.id)
        end
      end
    )
  end
end
