# typed: strict
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::CodeScanning::AdvancedSetupController < AbstractRepositoryController
  before_action :manage_security_products_permission_required

  sig { void }
  def update
    response = GitHub::Turboscan.set_advanced_setup_requested(repository_id: current_repository.id, advanced_setup_requested: true)
    raise StandardError.new("Failed to set advanced setup requested: #{response&.error}") if response.nil? || response.error.present?

    redirect_to helpers.code_scanning_codeql_template_url(current_repository)
  end
end
