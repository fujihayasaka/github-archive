# typed: true
# frozen_string_literal: true

class Spark::DashboardController < Spark::AbstractController
  depends_on_clusters(
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    only: [:show]
  )
  CSP_EXCEPTIONS = {
    frame_src: Rails.env.development? ? ["*.app.github.dev", "github.dev", "*.dev.github.dev", "dev.github.dev", "*.github.app"] : ["*.app.github.dev", "github.dev", "*.github.app"],
    connect_src: [
      "https://*.github.dev",
      "https://github.dev",
      "https://*.app.github.dev",
      "https://*.github.app",
      "*.blob.core.windows.net", # TODO: set specific storage account
    ],
    form_action: ["https://*.github.dev", "https://*.github.app"]
  }

  before_action :add_workbench_csp_exceptions, only: [:show]
  def show
    # Need to match client feature flags as our main controller because of soft navigation.
    if !helpers.current_user_has_copilot_license?
      session[:copilot_signup_redirect] = request.fullpath
      redirect_to copilot_signup_path
      return
    end
    add_client_feature_flag(Copilot::Workbench::EditorController::DEFAULT_CLIENT_FEATURE_FLAGS)
    context_region_preset :spark

    render_react_app(
      title: "Spark",
      app_payload_generator: -> { app_payload },
      page_data: {
        hide_footer: true,
      },
      disable_ssr: true,
      app_name: "workbench",
    )
  end

  private

  def app_payload
    {
      copilotChatSettingEnabled: false,
      searchWorkerFilePath: helpers.find_file_worker_path,
      ssoOrganizations: sso_organizations,
      copilotUpsellBannerDismissed: false,
      graphqlApiUrl: "/copilot/loops/loops_execution",
      previewUrl: Viewscreen.host_url,
      **helpers.copilot_chat_payload(false, saml_authorized_organizations(cap_filter, current_user), request),
    }.merge({ icebreakers: icebreakers_json })
  end

  sig { returns(T::Array[T.untyped]) }
  memoize def icebreakers_json
    file_path = Rails.root.join("config/spark-icebreakers.json")
    data = JSON.parse(File.read(file_path))
    [
      { type: "functional", data: data["functional"] || [] },
      { type: "instructional", data: data["instructional"] || [] },
      { type: "interactional", data: data["interactional"] || [] }
    ]
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def add_workbench_csp_exceptions
    exceptions = self.class.const_get(:CSP_EXCEPTIONS)
    if current_user&.feature_enabled?(:copilot_workbench_monaco_wasm)
      exceptions[:script_src] = ["'wasm-unsafe-eval'"]
      exceptions[:connect_src] += [GitHub.asset_host_url]
    end
    SecureHeaders.append_content_security_policy_directives(request, exceptions)
  end
end
