# typed: strict
# frozen_string_literal: true

module AppShell
  class StaffbarPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "staffbarRoute"
    end

    sig { params(canary_cookie_enabled: T::Boolean).void }
    def initialize(canary_cookie_enabled: false)
      @canary_cookie_enabled = canary_cookie_enabled
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def payload
      {
        apiEnvironment: api_environment,
        apiVersionRef: api_sha,
        uiEnvironment: ui_environment,
        uiVersionRef: ui_sha,
        canaryTogglePath: canary_toggle_path,
        canaryEnabled: @canary_cookie_enabled
      }
    end

    private

    sig { returns(String) }
    def environment_suffix
      if GitHub.multi_tenant_enterprise?
        ":proxima"
      elsif GitHub.enterprise?
        ":enterprise"
      else
        ""
      end
    end

    sig { returns(String) }
    def api_environment
      if Rails.env.development?
        "development#{environment_suffix}"
      elsif GitHub.heaven_env == "production/canary"
        "canary"
      elsif GitHub.role == :lab
        "lab"
      else
        "production#{environment_suffix}"
      end
    end

    sig { returns(T.nilable(String)) }
    def api_sha
      sha = GitHub.current_sha
      sha == "unknown" ? nil : sha
    end

    sig { returns(GitHubUI::Manifest) }
    def ui_manifest
      GitHubUI::Manifest.new
    end

    sig { returns(T.nilable(String)) }
    def ui_sha
      ui_manifest.ui_manifest_sha
    end

    sig { returns(String) }
    def ui_environment
      target = ui_manifest.ui_manifest_target

      if GitHub.ui_dev_server_enabled?
        "development"
      elsif target == "preview"
        "preview"
      elsif target.start_with?("canary-")
        "canary"
      else
        "production#{environment_suffix}"
      end
    end

    sig { returns(T.nilable(String)) }
    def canary_toggle_path
      Rails.application.routes.url_helpers.canary_path(toggle: !@canary_cookie_enabled) if GitHub.kubernetes_backend_available?
    end
  end
end
