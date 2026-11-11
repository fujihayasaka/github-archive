# typed: true
# frozen_string_literal: true

class Users::SearchesController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:show]

  def show
    search_params = { q: "user:#{params[:user_id]} #{params[:q]}" }
    search_params[:type] = params[:type] if params[:type]
    redirect_to search_path(search_params)
  end

  protected

  def target_for_conditional_access
    user = User.find_by(id: params[:user_id])
    user ? user : :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
