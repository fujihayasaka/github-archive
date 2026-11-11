# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettingsController < Orgs::CopilotSettings::BaseController
  include WithParameterValidation

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities

  def index
    if org_has_copilot_access?
      redirect_to add_with_param_to_path(settings_org_copilot_seat_management_path(current_organization), params)
    else
      redirect_to add_with_param_to_path(settings_org_copilot_enable_path(current_organization), params)
    end
  end

  private

  memoize def copilot_organization
    ::Copilot::Organization.new(current_organization)
  end

  sig { returns(T::Boolean) }
  def org_has_copilot_access?
    copilot_organization.has_copilot_for_business? || copilot_organization.has_trial?
  end
end
