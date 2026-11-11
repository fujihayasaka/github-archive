# typed: true
# frozen_string_literal: true

class Orgs::AgentSourcesController < Orgs::Controller
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
    this_organization
  end
end
