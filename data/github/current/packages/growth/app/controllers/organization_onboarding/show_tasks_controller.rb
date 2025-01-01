# typed: true
# frozen_string_literal: true

class OrganizationOnboarding::ShowTasksController < OrganizationOnboarding::ApplicationController
  before_action :non_emu_required

  def update
    this_organization.update(
      show_onboarding_tasks: ActiveModel::Type::Boolean.new.cast(params[:show_onboarding_tasks])
    )
    redirect_back fallback_location: user_path(this_organization)
  end
end
