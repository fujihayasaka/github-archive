# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::CustomInstructionsController < Orgs::CopilotSettings::BaseController
  include JsonDependency
  include VerifiedFetchDependency

  before_action :dotcom_required
  before_action :require_feature_flag
  before_action :org_admins_only
  # See: https://github.com/github/copilot-core-productivity/issues/1219
  # See: https://github.com/github/copilot-core-productivity/issues/1810
  before_action :require_can_change_copilot_enterprise_settings

  javascript_bundle :copilot

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    only: [:show]

  sig { void }
  def show
    render "settings/organization/copilot/custom_instructions/show", locals: {
      custom_instructions: custom_instructions,
      suggestions: suggestions
    }
  end

  sig { void }
  def create
    # This does an upsert. If the prompt is missing it will create one. Otherwise, it will update
    custom_instructions.prompt = custom_instructions_params[:prompt]
    if custom_instructions.save
      flash[:notice] = "Custom instructions updated"
      redirect_to settings_org_copilot_custom_instructions_path
    else
      flash[:error] = custom_instructions.errors.full_messages.to_sentence
      render "settings/organization/copilot/custom_instructions/show", locals: {
        custom_instructions: custom_instructions,
        suggestions: suggestions
       }
    end
  end

  private

  memoize def custom_instructions
    Copilot::CustomInstructions.find_or_initialize_by(owner_id: current_organization.id, owner_type: "Organization")
  end

  # List of suggestions that user's can click to get ideas for custom instructions
  #
  # The key is the text that will appear in the button. The value is the full
  # text that will be inserted into the textarea.
  def suggestions
    {
      "Code": "Prefer writing <language> if no language is specified.",
      "Dependencies": "Use <package manager> for <language> dependencies",
      "Knowledge bases": "Prioritize <knowledge base> when asking about <topic>.",
      "Responses": "Respond with <bullet points/minimal preamble>.",
    }
  end

  def custom_instructions_params
    params.require(:copilot_custom_instructions).permit(:prompt)
  end

  def require_feature_flag
    render_404 unless user_or_global_feature_enabled?(:copilot_chat_custom_instructions)
  end

  sig { void }
  def require_can_change_copilot_enterprise_settings
    render_404 unless copilot_organization.can_use_copilot_enterprise_features?
  end
end
