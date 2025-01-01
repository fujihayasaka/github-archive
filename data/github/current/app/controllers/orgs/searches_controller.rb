# typed: true
# frozen_string_literal: true

class Orgs::SearchesController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    search_params = { q: "org:#{params[:org]} #{params[:q]}" }
    search_params[:type] = params[:type] if params[:type]
    redirect_to search_path(search_params)
  end

  protected

  def target_for_conditional_access
    Organization.find_by(id: params[:org]) || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
