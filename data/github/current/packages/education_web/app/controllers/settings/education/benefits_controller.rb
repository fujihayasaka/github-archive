# typed: strict
# frozen_string_literal: true

class Settings::Education::BenefitsController < ApplicationController
  include Settings::ControllerMethods
  include Settings::Education::DeveloperPackApplications::SharedControllerMethods

  depends_on_clusters(
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index],
  )

  sig { void }
  def index
    render(
      Settings::Education::BenefitsComponent.new(
        user: current_user,
        page: params.fetch(:page, 1).to_i,
        utm_source: params[:utm_source],
        utm_content: params[:utm_content],
      ),
      layout: "user_settings",
    )
  end
end
