# typed: true
# frozen_string_literal: true

class Settings::AgentSourcesController < ApplicationController
  include AgentSourcesControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories,
    only: [:show, :new]

  javascript_bundle :settings
  stylesheet_bundle :settings

  private

  def current_context
    current_user
  end

  def target_for_conditional_access
    if logged_in?
      current_user
    else
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end
  end
end
