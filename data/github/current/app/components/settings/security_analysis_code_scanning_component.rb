# typed: strict
# frozen_string_literal: true

module Settings
  class SecurityAnalysisCodeScanningComponent < ApplicationComponent
    extend T::Sig

    include GitHub::Memoizer
    include SecurityAnalysisSettingsHelper

    sig { returns(::Organization) }
    attr_reader :owner

    sig { returns(Integer) }
    attr_reader :repo_count, :public_repo_count

    sig { returns(BlockedSettings) }
    attr_reader :blocked_settings

    sig { params(owner: ::Organization, repo_count: Integer, public_repo_count: Integer, blocked_settings: T.nilable(BlockedSettings)).void }
    def initialize(owner:, repo_count:, public_repo_count:, blocked_settings: nil)
      @owner = owner
      @repo_count = repo_count
      @public_repo_count = public_repo_count
      @blocked_settings = T.let(blocked_settings || BlockedSettings.new(owner), BlockedSettings)
    end

    sig { returns(T::Boolean) }
    def render?
      render_code_scanning_component?(owner)
    end

    sig { returns(String) }
    def security_analysis_update_path
      settings_org_security_analysis_update_path(owner, owner: owner)
    end

    sig { returns(String) }
    def model_packs_path
      settings_org_code_scanning_model_packs_path(organization_id: @owner.display_login)
    end

    sig { returns(T::Boolean) }
    def codeql_analysis_expansion_unavailable?
      !!(GitHub.enterprise? && ENV["CONTAINERS_PROTO_ENABLED"] != "true")
    end
  end
end
