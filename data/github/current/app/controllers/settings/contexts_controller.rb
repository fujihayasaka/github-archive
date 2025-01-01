# typed: true
# frozen_string_literal: true

class Settings::ContextsController < ApplicationController
  include SettingsHelper
  include OrganizationsHelper

  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    only: [:show]

  def show
    current_context = params[:context_type] == "user" ? current_user : current_organization
    contexts = if current_context
      available_contexts(current_context: current_context)
    else
      []
    end

    render partial: "settings/list_partial", locals: {
      current_context: current_context,
      available_contexts: contexts
    }
  end
end
