# typed: true
# frozen_string_literal: true

class CodespacesSiteScopedIntegrationInstallation < ApplicationRecord::Domain::IntegrationsLodge
  belongs_to :codespace, optional: false
  belongs_to :site_scoped_integration_installation, optional: false
end
