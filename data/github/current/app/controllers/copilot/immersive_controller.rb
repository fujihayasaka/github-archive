# typed: true
# frozen_string_literal: true

class Copilot::ImmersiveController < Copilot::Chat::AbstractChatController
  include CopilotForDocsHelper

  skip_before_action :require_feature_enabled

  prepend_before_action :login_required
  before_action :require_topic_to_exist

  stylesheet_bundle "copilot-markdown-rendering", "code", "copilot-immersive"

  helper_method :copilot_immersive_v1_enabled?

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
    only: [:show]
  )

  def show
    context_region_preset :copilot

    if copilot_immersive_v1_enabled?
      bundle_name = "copilot-immersive-v1"
      add_client_feature_flag([:graphql_subscriptions])
    else
      bundle_name = "copilot-immersive"
    end

    if feature_enabled?
      # copilot licensed
      render_react_app(
        title: params[:thread_id] ? "GitHub Copilot" : "New conversation · GitHub Copilot",
        payload: app_payload,
        page_data: {
          hide_footer: true,
        },
        ssr: false,
        app_name: bundle_name,
      )
    elsif !params[:thread_id]
      # unlicensed, show a welcome page
      render_react_app(
        title: "GitHub Copilot",
        payload: {},
        page_data: {
          hide_footer: true,
        },
        ssr: false,
        app_name: "copilot-immersive-unlicensed",
      )
    else
      render_404
    end
  end

  private

  def app_payload
    user = T.must(current_user)

    {
      threadID: params[:thread_id],
      searchWorkerFilePath: find_file_worker_path,
      requestedTopic: helpers.repo_props(repo: current_repository) || current_docset,
      ssoOrganizations: sso_organizations,
      **helpers.copilot_chat_payload(false, request),
    }
  end

  def require_topic_to_exist
    if params[:user_id] && params[:repository]
      render_404 unless current_repository
    elsif params[:docset_name]
      render_404 unless current_docset
    end
  end

  memoize def copilot_immersive_v1_enabled?
    return false unless user_feature_enabled?(:copilot_immersive_v1)
    return true if user_feature_enabled?(:copilot_immersive_v1_force)

    copilot_user = T.must(current_copilot_user_v2)
    if copilot_user.has_ce_access? || copilot_user.has_cb_access?
      copilot_user.beta_features_github_chat_enabled?
    else
      copilot_user.has_ci_access?
    end
  end

  memoize def current_repository
    return unless params[:user_id] && params[:repository]
    Repository.with_name_with_owner(params[:user_id], params[:repository])
  end

  memoize def current_docset
    return unless params[:docset_name]
    docset = find_docset(params[:docset_name])
    docset = secure_and_decorate_docset(docset) if docset
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
end
