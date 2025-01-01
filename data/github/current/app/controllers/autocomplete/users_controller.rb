# typed: true
# frozen_string_literal: true

class Autocomplete::UsersController < ApplicationController
  before_action :login_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    respond_to do |format|
      view = create_view_model(AutocompleteView, query: params[:q])
      visible_suggestions = cap_filter.authorized_resources(view.suggestions)
      format.html_fragment do
        render partial: "users/autocomplete", formats: :html, locals: {
          view: view,
          suggestions: visible_suggestions
        }
      end
      format.html do
        return head :not_acceptable unless request.xhr?
        render partial: "users/autocomplete", locals: {
          view: view,
          suggestions: visible_suggestions
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
