# typed: true
# frozen_string_literal: true

class Settings::IntegrationTransfersController < ApplicationController

  include IntegrationTransfersControllerMethods

  # The following actions do not require conditional access checks because
  # they *don't* access any protected organization resources.
  # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :perform_conditional_access_checks, only: %w(
    show
    accept
    destroy
  )

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  private

  def current_context
    current_user
  end
end
