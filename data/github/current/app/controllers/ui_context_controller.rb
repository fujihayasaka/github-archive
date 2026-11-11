# typed: true
# frozen_string_literal: true

class UIContextController < ApplicationController
  delegate :client_env, to: :view_context

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:show]

  def show
    render json: { clientEnv: client_env }
  end

  private

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end
end
