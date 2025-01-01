# typed: strict
# frozen_string_literal: true

class Memexes::WorkflowsConfigurationController < Memexes::Controller
  include MemexesHelper

  before_action :disable_color_modes
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :user_has_read_access
  before_action :set_client_uid

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    only: [:index]

  sig { void }
  def index
    render(json: { workflowConfigurations: this_memex.workflow_configurations(current_user).map(&:to_hash) })
  end
end
