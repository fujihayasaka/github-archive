# typed: true
# frozen_string_literal: true

class IntegrationInstallTrigger < ApplicationRecord::Domain::Integrations

  belongs_to :integration

  enum :install_type, {
    user_created: 0,
    file_added: 1,
    editor_opened: 2, # no longer used
    team_sync_enabled: 3,
    dependency_graph_initialized: 4,
    page_build: 5,
    dependency_update_requested: 6,
    automatic_security_updates_initialized: 7,
    pending_dependabot_installation_requested: 8,
    button_clicked: 9,
    oauth_code_exchanged: 10,
    dependabot_repository_access_updated: 11,
    actions_automatic_installation: 12,
    runtime_enable_api: 13, # no longer used
    dependabot_jit_access_requested: 14,
  }

  # Returns the latest trigger of each type for each integration.
  # Excludes deactivated triggers.
  scope :by_install_type, -> (install_type) {
    return none unless wanted_type = install_types[install_type]

    scope = joins(<<~SQL)
      JOIN (SELECT MAX(id) AS max_id
            FROM integration_install_triggers
            WHERE integration_install_triggers.install_type = #{wanted_type}
              GROUP BY install_type, integration_id)
          AS subquery
      ON integration_install_triggers.id = subquery.max_id
    SQL
    scope.where(deactivated: false)
  }

  validates :integration, presence: { message: "GitHub App ID is required and must be an existing GitHub App." }
  validate :validate_trigger, on: :create

  def self.deactivate(integration:, install_type:)
    latest = latest(integration: integration, install_type: install_type)
    return latest if latest&.deactivated?
    create(integration: integration, install_type: install_type, deactivated: true)
  end

  def self.latest(integration:, install_type:)
    where(integration: integration).where("install_type = ?", install_types[install_type]).last
  end

  def handler
    AutomaticAppInstallation::TRIGGER_HANDLERS[install_type.to_sym]
  end

  def after_integration_installed(**args)
    return unless handler.respond_to?(:after_integration_installed)
    handler.after_integration_installed(**args)
  end

  # Callback from the `InstallAutomaticIntegrations` background job if a trigger is
  # fired but the App is already installed on the target.
  #
  # Trigger handlers should implement the class method
  # `.integration_already_installed` to handle any custom behavior they need.
  def integration_already_installed(**args)
    return unless handler.respond_to?(:integration_already_installed)
    handler.integration_already_installed(**args)
  end

  def should_install?(**args)
    return true unless handler.respond_to?(:should_install?)
    handler.should_install?(**args)
  end

  def validate_trigger
    return true unless handler.respond_to?(:validate_trigger)
    handler.validate_trigger(self)
  end
end
