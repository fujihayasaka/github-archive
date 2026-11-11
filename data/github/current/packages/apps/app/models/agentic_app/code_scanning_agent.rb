# typed: strict
# frozen_string_literal: true

module AgenticApp
  # Code Scanning Agent - Global agent for code scanning tasks
  class CodeScanningAgent < Base
    sig { override.returns(String) }
    def slug
      Apps::Privileged::CodeScanning::GHAS_BOT_LOGIN
    end

    sig { override.returns(String) }
    def display_name
      "GitHub Advanced Security"
    end

    sig { override.returns(String) }
    def display_owner
      "GitHub"
    end

    sig { override.returns(String) }
    def doc_url
      DocsUrlConfig.url_for("about-autofix")
    end

    sig { override.returns(Symbol) }
    def privileged_app_alias
      :code_scanning
    end

    sig { override.returns(Symbol) }
    def disallow_feature_flag
      :code_scanning_ai_findings_disallow
    end

    # policy_feature_flag is required by Base but not used for this agent — access
    # is instead controlled via repository Advanced Security configuration in
    # enabled_for_repository?.
    sig { override.returns(Symbol) }
    def policy_feature_flag
      :code_scanning_agent
    end

    sig { override.returns(T::Boolean) }
    def assignable?
      false
    end

    sig { override.returns(T::Boolean) }
    def mentionable?
      false
    end

    sig { override.returns(T::Boolean) }
    def global?
      true
    end

    sig { override.returns(AgenticApp::Group) }
    def group
      AgenticApp::Group::AUTOMATION
    end

    sig { override.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
    def installed_for_target?(target)
      true  # Global agent - always installed
    end

    sig { override.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
    def can_be_enabled_for?(target)
      true
    end

    sig do
      override.params(
        repo: T.untyped,
        viewer: T.untyped
      ).returns(T::Boolean)
    end
    def enabled_for_repository?(repo, viewer)
      # Global agent - check repository-level enablement
      return false unless integration

      repo.code_scanning_usable?
    end
  end
end
