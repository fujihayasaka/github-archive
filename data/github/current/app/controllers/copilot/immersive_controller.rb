# typed: true
# frozen_string_literal: true

class Copilot::ImmersiveController < Copilot::Chat::AbstractChatController
  skip_before_action :require_feature_enabled
  skip_before_action :require_logged_in_user, only: [:logged_out_show, :logged_out_shared_view, :authenticate_prompt]
  skip_before_action :require_user_can_read_repo, only: [:logged_out_show, :logged_out_shared_view, :authenticate_prompt]
  prepend_before_action :login_required, except: [:logged_out_show, :logged_out_shared_view, :authenticate_prompt]
  before_action :require_read_access_to_shared_thread, except: [:logged_out_shared_view, :authenticate_prompt]
  before_action :require_topic_to_exist
  before_action :add_csp_exceptions, only: :show

  before_action :conditionally_initialize_global_sso, only: :show
  before_action :check_custom_copilot_routes, only: :show

  before_action :enable_fullstory, only: :logged_out_show
  before_action :add_fullstory_csp_exceptions, only: :logged_out_show

  stylesheet_bundle "copilot-markdown-rendering", "code", "copilot-immersive"

  allow_verified_fetch only: [:authenticate_prompt]

  CSP_EXCEPTIONS = {
    img_src: [GitHub.figma_image_thumbnail_url, GitHub.figma_full_image_url] +
      ::Copilot::ChatAttachment.primary_and_secondary_abs_urls,
    # Allow fetching of chat images from the blob storage
    connect_src: ::Copilot::ChatAttachment.primary_and_secondary_abs_urls,
  }

  COPILOT_MODELS_KEY = "github.copilot.chat.models"

  depends_on_clusters(
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    only: [:show, :logged_out_show]
  )

  depends_on_clusters(
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    only: [:show, :logged_out_show, :logged_out_shared_view]
  )

  depends_on_clusters(
    ApplicationRecord::IssuesPullRequests,
    only: [:show, :logged_out_show],
    optional: true,
  )

  def show
    add_client_feature_flag([
      :copilot_pipes_react_nodes,
      :copilot_pipes_github_graphql_nodes,
      :copilot_pipes_pipeline_nodes,
      :copilot_loops_post_staff_ship_features,
      :copilot_pro_plus_animation,
      :copilot_premium_request_quotas,
      :issue_dependencies
    ])

    context_region_preset :copilot

    # Allow access for shared threads even without a full Copilot license
    # when thread sharing is enabled on the instance
    is_shared_thread = params[:shared_thread]
    thread_sharing_enabled = CopilotPLG.domain.copilot_thread_sharing_enabled?

    if helpers.current_user_has_copilot_license? || (is_shared_thread && thread_sharing_enabled)
      # Redirect to the immersive experience with model and prompt information if they are available in the session
      return if redirect_to_prepopulated_show

      show_title = if params[:thread_id].present?
        "GitHub Copilot"
      elsif request.path == copilot_agents_show_path
        "Agents · GitHub Copilot"
      elsif request.path.starts_with?(copilot_spaces_list_path)
        "Spaces · GitHub Copilot"
      else
        "New conversation · GitHub Copilot"
      end

      staffbar_enabled = current_user&.feature_flag_enabled?(:copilot_immersive_staffbar, default: false)
      classes = [
        "copilotImmersive",
        ("copilotImmersiveHideStaffbar" unless helpers.hide_site_header? && staffbar_enabled)
      ].compact.join(" ")

      render_react_app(
        title: show_title,
        app_payload_generator: -> {
          payload = app_payload

          if helpers.hide_site_header?
            payload.merge!(global_sso_app_payload)
          end

          payload
        },
        page_data: {
          class: classes,
          hide_header_content: helpers.hide_site_header? && staffbar_enabled,
          hide_header: helpers.hide_site_header? && !staffbar_enabled,
          hide_footer: true,
          richweb: copilot_richweb_metadata,
          noindex_and_nofollow: true,
        },
        disable_ssr: true,
        app_name: "copilot-immersive-v1",
      )
    else
      prompt = params[:prompt].presence
      model = params[:model].presence

      session[:skip_copilot_signup_email] = true if params[:shared_thread]
      session[:copilot_immersive_prompt] = prompt if prompt
      session[:copilot_immersive_model] = model if model

      redirect_to :copilot_signup
    end
  end

  def logged_out_show # rubocop:todo GitHub/UseRestfulActions
    return redirect_to(:copilot_signup) unless logged_out_experience_enabled?

    render_react_app(
      title: "GitHub Copilot",
      app_payload_generator: -> { logged_out_payload },
      page_data: {
        hide_header: true,
        hide_footer: true,
        richweb: copilot_richweb_metadata,
      },
      disable_ssr: true,
      app_name: "copilot-immersive-logged-out",
    )
  end

  def logged_out_shared_view # rubocop:todo GitHub/UseRestfulActions
    return redirect_to_login(request.url) unless robot?

    render "copilot/immersive/logged_out_shared_view",
      layout: true,
      locals: {
        page_data: {
          title: "GitHub Copilot",
          richweb: copilot_richweb_metadata,
          noindex_and_nofollow: true,
        }
      }
  end

  def authenticate_prompt # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless logged_out_experience_enabled?

    session[:copilot_auto_submit_prompt] = true

    immersive_path =
      helpers.copilot_immersive_path(
        model: params[:model].to_s.presence,
        prompt: params[:prompt].to_s.presence,
      )
    sign_in_path = helpers.login_path(return_to: immersive_path)

    case params[:via]
    when "sign_in"
      redirect_to sign_in_path, status: :see_other
    when "sign_up"
      redirect_to helpers.new_nux_signup_path(return_to: sign_in_path), status: :see_other
    else
      render_404
    end
  end

  private

  def conditionally_initialize_global_sso
    return if helpers.hide_site_header?

    initialize_global_sso_prompt
  end

  # Return 404 if the user does not have the custom copilots feature flag enabled
  def check_custom_copilot_routes
    return unless CopilotSpaces::RouteHelper.custom_copilots_immersive_route?(request, params)
    return if copilot_spaces_enabled?

    if user_feature_enabled?(:copilot_custom_copilots_feature_preview_redirect)
      redirect_to_custom_copilots_feature_preview
    else
      render_404
    end
  end

  def app_payload
    user = T.must(current_user)

    payload = {
      copilotChatSettingEnabled: helpers.copilot_chat_enabled_for_current_user?,
      searchWorkerFilePath: find_file_worker_path,
      requestedTopic: helpers.repo_props(repo: current_repository) || current_docset,
      ssoOrganizations: sso_organizations,
      copilotUpsellBannerDismissed: user.settings.get(:copilot_editor_upsell_banner_dismissed),
      icebreakers: helpers.get_icebreakers_json,
      graphqlApiUrl: "/copilot/loops/loops_execution",
      loopsClientUrl: "/copilot/loops/client",
      previewUrl: Viewscreen.host_url,
      helpUrl: GitHub.help_url,
      apiVersion: copilot_api_version,
      sharedThreadChannel: shared_thread_channel,
      autoSubmit: auto_submit_prompt?,
      **helpers.copilot_chat_payload(false, saml_authorized_organizations(cap_filter, user), request),
      spark: {
        icebreakers: helpers.get_spark_icebreakers_json,
      },
      copilotSpacesConfig: {
        maxDescriptionLength: CopilotSpace::MAX_DESCRIPTION_LENGTH,
        maxGeneralInstructionsLength: CopilotSpace::MAX_GENERAL_INSTRUCTIONS_LENGTH,
        maxContentSize: CopilotSpace.max_content_size(current_user),
        maxResourceCount: CopilotSpace::MAX_RESOURCE_COUNT,
        userHasOrgs: user.organizations.exists?,
      },
      agentsEnabled: Copilot::Public::User.new(user).swe_agent_enabled?,
      showCopilotCodingAgentPremiumRequestsBanner: CopilotSweAgent::Public.show_copilot_coding_agent_premium_requests_banner(user),
      sparkEnabled: current_user.spark_enabled?,
    }

    payload[:figmaAuthUrl] = figma_auth_url if current_user.feature_flag_enabled?(:copilot_immersive_figma_integration, default: false)

    if (request.referrer &&
      is_new_thread?)
      reference = reference_from_referrer
      payload[:reference] = reference if reference
    end

    payload
  end

  sig { returns(T.nilable(Reference)) }
  def reference_from_referrer
    referrer = URI.parse(request.referrer)
    server = URI.parse(GitHub.url)
    return nil unless referrer.is_a?(URI::HTTP) && server.is_a?(URI::HTTP) && referrer.origin == server.origin
    reference = reference_from_path(referrer.path)
  rescue URI::InvalidURIError
    nil
  end

  sig { params(path: T.nilable(String)).returns(T.nilable(Reference)) }
  def reference_from_path(path)
    chat_link_item = Copilot::ChatLinkItem.new(path, current_user)
    chat_link_item.reference
  rescue ActiveRecord::ActiveRecordError
    nil # for db fallback
  end

  sig { returns(T.nilable(String)) }
  def copilot_api_version
    if current_user&.feature_flag_enabled?(:copilot_api_version_20250501, default: false)
      CopilotAPI::VERSION_2025_05_01
    else
      nil
    end
  end

  memoize def shared_thread_channel
    return nil unless params[:shared_thread]
    GitHub::WebSocket::Channels.signed_copilot_shared_thread(params[:thread_id])
  end

  memoize def auto_submit_prompt?
    session.delete(:copilot_auto_submit_prompt).present?
  end

  memoize def models
    models = []
    models_json =
      ActiveRecord::Base.connected_to(role: :reading) do
        CopilotPLG::KV.get(COPILOT_MODELS_KEY).value { nil }
      end

    return JSON.parse(models_json) if models_json

    models_data =
      CopilotAPI.make_request(
        copilot_api_version: CopilotAPI::VERSION_2025_05_01,
        experiment_headers: { "X-Experiment-Include-Models-Billing" => "enabled" },
        integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID,
        method: :get,
        path: "/models",
        real_ip: nil,
        token: nil,
        user_id: nil,
      )["data"]

    return [] unless models_data

    models =
      models_data.select do |model|
        model["model_picker_enabled"] &&
          !model["preview"] &&
          model.dig("capabilities", "type") == "chat" &&
          model.dig("billing", "restricted_to").blank?
      end

    ActiveRecord::Base.connected_to(role: :writing) do
      CopilotPLG::KV.set(COPILOT_MODELS_KEY, models.to_json, expires: 6.hours.from_now)
    end

    models
  rescue StandardError => e # rubocop:disable Lint/RescueException
    Rails.logger.error("Error fetching models: #{e.message}")
    models
  end

  def logged_out_payload
    {
      models:,
      promptPath: helpers.copilot_authenticate_prompt_path,
      signInPath: helpers.login_path(return_to: helpers.copilot_immersive_path),
      signUpPath: helpers.new_nux_signup_path(return_to: helpers.copilot_immersive_path),
    }
  end

  # returns true if this is a new thread in hyperspace
  sig { returns(T::Boolean) }
  def is_new_thread?
    request.path == "/copilot"
  end

  memoize def logged_out_experience_enabled?
    CopilotPLG.domain.logged_out_copilot_chat_enabled?(request, user: current_user)
  end

  def require_topic_to_exist
    if params[:user_id] && params[:repository]
      render_404 unless current_repository
    elsif params[:docset_name]
      render_404 unless current_docset
    end
  end

  memoize def current_repository
    return nil unless params[:user_id] && params[:repository]
    Repository.with_name_with_owner(params[:user_id], params[:repository])
  end

  memoize def current_docset
    return nil unless params[:docset_name]

    docset = KnowledgeBases::Public.find_docset(current_user_copilot_api:, docset_name_or_id: params[:docset_name])
    docset = KnowledgeBases::Public.secure_and_decorate_docset(current_user:, cap_filter:, docset:) if docset
    docset
  end

  def figma_auth_url
    server = CopilotMcp::Query.find_mcp_server_by_name("figma")
    return nil unless server
    mcp_authorization_new_path(mcp_server_id: server.id)
  end

  # CAP is not bypassed here as :require_topic_to_exist 404s unless current_repository exists.
  def resource_for_conditional_access
    return current_repository if current_repository
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return current_repository.owner if current_repository
    return current_user if logged_in?
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def require_read_access_to_shared_thread
    if params[:shared_thread] # Set in config/routes/copilot.rb
      # For shared threads, only require that thread sharing is enabled on the instance
      # Anyone with a valid shared link should be able to view it
      unless CopilotPLG.domain.copilot_thread_sharing_enabled?
        render_404
      end
    end
  end

  def redirect_to_prepopulated_show
    prompt = session.delete(:copilot_immersive_prompt).presence
    model = session.delete(:copilot_immersive_model).presence

    if prompt || model
      redirect_to copilot_immersive_path(prompt:, model:)
      true
    else
      false
    end
  end

  # Returns a hash of richweb metadata used for social media cards and sharing
  def copilot_richweb_metadata
    {
      title: "GitHub Copilot",
      type: "website",
      url: T.must(request).original_url,
      description: "AI that builds with you",
      image: image_url("modules/site/social-cards/copilot-chat.png")
    }
  end
end
