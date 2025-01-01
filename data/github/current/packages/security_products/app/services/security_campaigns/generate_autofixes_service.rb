# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class GenerateAutofixesService
    extend T::Sig

    sig { params(org: Organization, logical_alert_info: T::Hash[Integer, T::Array[Integer]]).void }
    def initialize(org, logical_alert_info)
      @org = org
      @logical_alert_info = logical_alert_info
    end

    sig { void }
    def call
      return unless CodeScanning::Autofix.enabled_for_org?(@org)
      return unless SecurityCampaigns.autofix_generation_enabled?(@org)

      repo_details = @logical_alert_info.map do |repository_id, alert_numbers|
        repo = Repositories::Public.find_active!(repository_id)
        next unless CodeScanning::Autofix.enabled_for_repo?(repo)

        default_ref = repo.default_branch_ref

        Turboscan::Proto::RepoAlertNumbers.new(
          repository_id: repository_id.to_i,
          alert_numbers:,
          ref_names_bytes: Array(default_ref.qualified_name.b),
        )
      end

      repo_details = repo_details.compact

      return if repo_details.empty?

      GitHub::Turboscan::SuggestedFixes.generate_suggested_fixes_for_repos(
        user_id: @org.id,
        repos: repo_details
      )
    end

    # org - The organization that the security campaign belongs to
    # logical_alert_info - Hash of {repo_id: [logical_alert_number1, logical_alert_number2, ..]} entries
    sig { params(org: Organization, logical_alert_info: T::Hash[Integer, T::Array[Integer]]).void }
    def self.call(org, logical_alert_info)
      new(org, logical_alert_info).call
    end
  end
end
