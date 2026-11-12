# frozen_string_literal: true

module ChatopDisable
  extend ActiveSupport::Concern

  FIDO_PROTECTED_ACTIONS = %i(disable_ecosystem_repo enable_ecosystem_repo disable_ecosystem_percentage).freeze

  # rubocop:disable Metrics/BlockLength
  included do
    before_action :require_fido_2fa, only: FIDO_PROTECTED_ACTIONS

    chatop :disable_ecosystem_repo,
           /disable\s+(?<ecosystem>\S*)\s+(?<nwo>\S*)/,
           "disable <ecosystem> <nwo> [--tenant TENANT] - Disable running jobs in ecosystem on repo" do
      ecosystem = jsonrpc_params[:ecosystem]
      nwo = jsonrpc_params[:nwo]
      tenant = jsonrpc_params[:tenant]

      unless ParseConfigFile::PACKAGE_MANAGER_LOOKUP.invert.key?(ecosystem)
        jsonrpc_error "Unknown ecosystem: #{ecosystem}"
        return
      end

      repo = find_by_nwo!(nwo, tenant)
      repo.enable_feature("disable_#{ecosystem}_jobs") # rubocop:disable Dependabot/NoLocalFeatureFlags
      jsonrpc_success "Dropping `#{ecosystem}` jobs on `#{nwo}`"
    end

    chatop :enable_ecosystem_repo,
           /enable\s+(?<ecosystem>\S*)\s+(?<nwo>\S*)/,
           "enable <ecosystem> <nwo> [--tenant TENANT] - Enable running jobs in ecosystem on repo" do
      ecosystem = jsonrpc_params[:ecosystem]
      nwo = jsonrpc_params[:nwo]
      tenant = jsonrpc_params[:tenant]

      unless ParseConfigFile::PACKAGE_MANAGER_LOOKUP.invert.key?(ecosystem)
        jsonrpc_error "Unknown ecosystem: #{ecosystem}"
        return
      end

      repo = find_by_nwo!(nwo, tenant)
      repo.disable_feature("disable_#{ecosystem}_jobs") # rubocop:disable Dependabot/NoLocalFeatureFlags
      jsonrpc_success "Processing `#{ecosystem}` jobs on `#{nwo}`"
    end

    chatop :disable_ecosystem_percentage,
           /disable\s+(?<ecosystem>\S*)\s+rollout\s+(?<percentage>\S*)/,
           "disable <ecosystem> rollout <percentage> - Disable jobs in ecosystem for a percentage of repos" do
      ecosystem = jsonrpc_params[:ecosystem]
      # Support a humanized percentage value by dropping any trailing %
      percentage = jsonrpc_params[:percentage].chomp("%")

      unless ParseConfigFile::PACKAGE_MANAGER_LOOKUP.invert.key?(ecosystem)
        jsonrpc_error "Unknown ecosystem: #{ecosystem}"
        return
      end

      ChatopRolloutFeatures.rollout("disable_#{ecosystem}_jobs", percentage)
    end
  end
  # rubocop:enable Metrics/BlockLength
end
