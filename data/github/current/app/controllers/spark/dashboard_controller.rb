# typed: true
# frozen_string_literal: true

class Spark::DashboardController < Spark::AbstractController
  include MonacoMethods

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

  frame_src_domains = ["blob:", "*.app.github.dev", "github.dev", "*.github.app", "*.users.github.app"]
  frame_src_domains_dev = frame_src_domains + ["*.dev.github.dev", "dev.github.dev"]
  connect_src_domains = [
      "https://*.github.dev",
      "https://github.dev",
      "https://*.app.github.dev",
      "https://*.github.app",
      "https://*.users.github.app",
      "*.blob.core.windows.net", # TODO: set specific storage account
      "https://scanning-api.github.com", # secret scanning public API
  ]
  connect_src_domains_dev = connect_src_domains + [
    "http://localhost:5001" # secret scanning public API (dev)
  ]

  CSP_EXCEPTIONS = {
    frame_src: Rails.env.development? ? frame_src_domains_dev : frame_src_domains,
    connect_src: Rails.env.development? ? connect_src_domains_dev : connect_src_domains,
    form_action: ["https://*.github.dev", "https://*.github.app", "https://*.users.github.app"],
    media_src: ["blob:"],
    object_src: ["blob:"],
  }

  before_action :add_workbench_csp_exceptions, only: [:show]
  before_action :require_feature_enabled, only: [:show]
  preload_features Copilot::Workbench::EditorController::DEFAULT_CLIENT_FEATURE_FLAGS, only: [:show]

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

  sig { returns(String) }
  def manifest_href
    "/copilot/spark/manifest.json"
  end

  def app_payload
    {
      copilotChatSettingEnabled: false,
      searchWorkerFilePath: helpers.find_file_worker_path,
      ssoOrganizations: sso_organizations,
      copilotUpsellBannerDismissed: false,
      graphqlApiUrl: "/copilot/loops/loops_execution",
      loopsClientUrl: "/copilot/loops/client",
      previewUrl: Viewscreen.host_url,
      sparkEnabled: current_user&.spark_enabled?,
      partOfSparkRollout: current_user&.part_of_spark_rollout?,
      markdownDocsUrl: GitHub.markdown_docs_url,
      monacoWorkerUrls: monaco_worker_paths(method(:web_worker_url)),
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
    if current_user&.feature_flag_enabled?(:copilot_workbench_monaco_wasm, default: false)
      exceptions[:script_src] = ["'wasm-unsafe-eval'"]
      exceptions[:connect_src] += [GitHub.asset_host_url]
    end
    SecureHeaders.append_content_security_policy_directives(request, exceptions)
  end

  # The Spark dashboard should be viewable for users, even if they don't have Spark enabled. This is needed for
  # allowing users to view previous Sparks in read-only mode, prompting users to have their admins enable Spark,
  # showing a "Coming soon" page, etc.
  sig { void }
  def require_feature_enabled
    render_404 unless current_user&.feature_flag_enabled?(:copilot_workbench, default: false) || current_user&.feature_flag_enabled?(:spark_coming_soon, default: false)
  end
end
