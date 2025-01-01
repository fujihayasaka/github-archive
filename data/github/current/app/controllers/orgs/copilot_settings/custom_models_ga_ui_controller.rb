# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::CustomModelsGaUIController < Orgs::CopilotSettings::BaseController
  extend GitHub::Memoizer

  include Orca::OrcaControllerHelper

  before_action :check_copilot_ga_available
  before_action :feature_required

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-custom-models-ga-ui"
  end

  sig { void }
  def index
    render_react_app(
      payload: {}.merge(paths),
      layout: "layouts/copilot/custom_models_ga_ui",
      title: "GitHub Copilot - Custom model",
    )
  end

  sig { void }
  def new
    render_react_app(
      payload: {}.merge(paths),
      layout: "layouts/copilot/custom_models_ga_ui",
      title: "GitHub Copilot - Custom model",
    )
  end

  sig { void }
  def assessing # rubocop:todo GitHub/UseRestfulActions
    render_react_app(
      payload: {}.merge(paths),
      layout: "layouts/copilot/custom_models_ga_ui",
      title: "GitHub Copilot - Custom model",
    )
  end

  sig { void }
  def assessment # rubocop:todo GitHub/UseRestfulActions
    render_react_app(
      payload: {}.merge(paths),
      layout: "layouts/copilot/custom_models_ga_ui",
      title: "GitHub Copilot - Custom model",
    )
  end

  sig { void }
  def training # rubocop:todo GitHub/UseRestfulActions
    render_react_app(
      payload: {}.merge(paths),
      layout: "layouts/copilot/custom_models_ga_ui",
      title: "GitHub Copilot - Custom model",
    )
  end

  private

  sig do returns({
    indexPath: String,
    newPath: String,
    assessingPath: String,
    assessmentPath: String,
    trainingPath: String,
  })
  end
  def paths
    {
      indexPath: custom_models_ga_ui_path,
      newPath: custom_models_ga_ui_new_path,
      assessingPath: custom_models_ga_ui_assessing_path,
      assessmentPath: custom_models_ga_ui_assessment_path,
      trainingPath: custom_models_ga_ui_training_path,
    }
  end
end
