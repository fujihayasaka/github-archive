# typed: true
# frozen_string_literal: true

class Search::CustomScopesController < ApplicationController
  before_action :require_feature_flags
  before_action :login_required

  include Search::Blackbird::Features

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:index]

  def index
    scopes = T.must(current_user).search_custom_scopes.order(:name)

    render json: scopes.to_json(root: nil, only: [:id, :name, :query])
  end

  def save # rubocop:todo GitHub/UseRestfulActions
    id = params[:custom_scope_id]
    name, query = params.require([:custom_scope_name, :custom_scope_query])

    if id.present?
      updated = T.must(current_user).search_custom_scopes.find(id).update(name: name, query: query)
      return head :ok if updated
    else
      scope = T.must(current_user).search_custom_scopes.create(name: name, query: query)
      return head :ok if scope.valid?
    end

    head :unprocessable_entity
  end

  def destroy
    T.must(current_user).search_custom_scopes.find(params.require(:id)).destroy

    head :ok
  end

  def check_name # rubocop:todo GitHub/UseRestfulActions
    name = params.require(:value)
    scope = T.must(current_user).search_custom_scopes.new(name: name, name_validation_only: true)

    if scope.valid?
      head :ok
    else
      render html: scope.errors.first.full_message, status: :unprocessable_entity
    end
  end

  private

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def require_feature_flags
    render_404 unless blackbird_enabled?
  end
end
