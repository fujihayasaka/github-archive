# typed: strict
# frozen_string_literal: true

module CodeScanning
  class AutoCodeqlScanInactiveRepos < SecurityProduct::Service
    include GitHub::Memoizer

    ERROR_MESSAGES = T.let({
      turboscan_set_scan_inactive_repo_failed: "Turboscan SetScanInactiveRepo endpoint failed",
    }, T::Hash[Symbol, String])

    sig { override.returns(T::Boolean) }
    def enabled?
      return false unless auto_codeql_service.enabled?

      scan_inactive_repos_enabled_for_repo?
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_enable?(actor:, options:)
      unless CodeScanning::ScanInactiveRepos.available_in_environment?
        return SecurityProduct::Result.new(false, :not_available_on_ghes)
      end

      unless CodeScanning::ScanInactiveRepos.feature_flag_enabled_for?(repository.organization)
        return SecurityProduct::Result.new(false, :feature_not_available)
      end

      unless auto_codeql_service.enabled?
        return SecurityProduct::Result.new(false, :default_setup_disabled)
      end

      SecurityProduct::Result.new(true)
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_enable(actor:, options:)
      response = GitHub::Turboscan::ManagedAnalyses.set_scan_inactive_repo(
        repository_id: repository.id,
        scan_when_inactive: true,
      )

      if response.nil? || response.error.present?
        error = CodeScanning::AutoCodeqlError.new(
          ERROR_MESSAGES.fetch(:turboscan_set_scan_inactive_repo_failed),
          repo_id: repository.id,
          twirp_error: response&.error,
        )
        return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options), error)
      end

      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options))
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_disable?(actor:, options:)
      SecurityProduct::Result.new(true)
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_disable(actor:, options:)
      response = GitHub::Turboscan::ManagedAnalyses.set_scan_inactive_repo(
        repository_id: repository.id,
        scan_when_inactive: false,
      )

      if response.nil? || response.error.present?
        error = CodeScanning::AutoCodeqlError.new(
          ERROR_MESSAGES.fetch(:turboscan_set_scan_inactive_repo_failed),
          repo_id: repository.id,
          twirp_error: response&.error,
        )
        return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options), error)
      end

      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options))
    end

    sig { override.returns(Symbol) }
    def to_sym
      :auto_codeql_scan_inactive_repos
    end

    sig { override.returns(String) }
    def self.name
      "Auto CodeQL scan inactive repos"
    end

    sig { override.params(symbol: T.nilable(SecurityProduct::Result::Error)).returns(String) }
    def self.error_to_message(symbol)
      case symbol
      when :not_available_on_ghes
        "Inactive repositories code scanning is not available on GitHub Enterprise Server."
      when :feature_not_available
        "Inactive repositories code scanning is not available for this repository."
      when :default_setup_disabled
        "Inactive repositories code scanning can only be enabled on repositories with code scanning default setup enabled."
      else
        "Failed to toggle inactive repositories code scanning."
      end
    end

    private

    sig { returns(CodeScanning::AutoCodeql) }
    memoize def auto_codeql_service
      CodeScanning::AutoCodeql.new(repository)
    end

    sig { returns(T::Boolean) }
    def scan_inactive_repos_enabled_for_repo?
      !!auto_codeql_service.configuration.scan_inactive_repos
    end
  end
end
