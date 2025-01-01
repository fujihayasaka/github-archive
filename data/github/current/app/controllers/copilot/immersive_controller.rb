# typed: true
# frozen_string_literal: true

class Copilot::ImmersiveController < Copilot::Chat::AbstractChatController
  skip_before_action :require_feature_enabled

  prepend_before_action :login_required
  before_action :require_read_access_to_shared_thread
  before_action :require_topic_to_exist
  before_action :add_csp_exceptions, only: :show

  stylesheet_bundle "copilot-markdown-rendering", "code", "copilot-immersive"

  CSP_EXCEPTIONS = {
    img_src: [GitHub.figma_image_thumbnail_url, GitHub.figma_full_image_url],
  }

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

  def show
    add_client_feature_flag([
      :copilot_immersive_file_preview_additional_formats,
      :copilot_immersive_preview_html_files,
      :copilot_immersive_edit_file,
      :copilot_immersive_view_system_prompt,
      :copilot_immersive_create_issue,
    ])

    # Return 404 if the user does not have the custom copilots feature flag enabled
    is_copilot_spaces_route = request.path == copilot_spaces_list_path || (params[:space_id] && request.path == copilot_spaces_show_path(space_id: params[:space_id]))
    return render_404 if is_copilot_spaces_route && !user_feature_enabled?(:copilot_custom_copilots)

    context_region_preset :copilot

    if helpers.current_user_has_copilot_license?
      render_react_app(
        title: params[:thread_id] ? "GitHub Copilot" : "New conversation · GitHub Copilot",
        app_payload_generator: -> { app_payload },
        page_data: {
          class: "copilotImmersive",
          hide_footer: true,
        },
        disable_ssr: true,
        app_name: "copilot-immersive-v1",
      )
    else
      redirect_to :copilot_signup
    end
  end

  private

  def app_payload
    user = T.must(current_user)
    user_for_create_issue = nil
    if user_feature_enabled?(:copilot_immersive_create_issue)
      user_for_create_issue = {
        avatarUrl: user.primary_avatar_url(40),
        id: user.id,
        login: user.display_login,
        name: user.name,
        is_emu: user.is_enterprise_managed?,
        analyticsTrackingId: user.analytics_tracking_id,
      }
    end

    {
      copilotChatSettingEnabled: helpers.copilot_chat_enabled_for_current_user?,
      searchWorkerFilePath: find_file_worker_path,
      requestedTopic: helpers.repo_props(repo: current_repository) || current_docset,
      ssoOrganizations: sso_organizations,
      copilotUpsellBannerDismissed: user.settings.get(:copilot_editor_upsell_banner_dismissed),
      icebreakers: helpers.get_icebreakers_json,
      current_user: user_for_create_issue,
      graphqlApiUrl: "/copilot/pipes/pipes_execution",
      previewUrl: Viewscreen.host_url,
      **helpers.copilot_chat_payload(false, saml_authorized_organizations(cap_filter, user), request),
    }
  end

  def require_topic_to_exist
    if params[:user_id] && params[:repository]
      render_404 unless current_repository
    elsif params[:docset_name]
      render_404 unless current_docset
    end
  end

  memoize def current_repository
    return unless params[:user_id] && params[:repository]
    Repository.with_name_with_owner(params[:user_id], params[:repository])
  end

  memoize def current_docset
    return unless params[:docset_name]

    docset = KnowledgeBases::Public.find_docset(current_user_copilot_api:, docset_name_or_id: params[:docset_name])
    docset = KnowledgeBases::Public.secure_and_decorate_docset(current_user:, cap_filter:, docset:) if docset
    docset
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
      render_404 unless CopilotPLG.domain.user_can_read_shared_copilot_thread?(current_user)
    end
  end
end
