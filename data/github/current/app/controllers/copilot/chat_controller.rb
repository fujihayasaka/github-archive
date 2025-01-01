# typed: true
# frozen_string_literal: true

class Copilot::ChatController < Copilot::Chat::AbstractChatController
  depends_on_clusters(
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:show],
  )

  def show
    # declare feature flags for client-side access in lib/github/client_side_feature_flags.rb
    # then use the `isFeatureEnabled` function from @github-ui/feature-flags

    user = T.must(current_user)

    render partial: "copilot/chat_show", locals: {
      props: {
        currentTopic: helpers.repo_props(repo: current_repository, ref_name: tree_name),
        findFileWorkerPath: find_file_worker_path,
        renderPopover: render_popover?,
        renderBetaLabel: helpers.render_beta_label?,
        chatIsVisible: current_user&.settings.get(:copilot_chat_visible),
        chatVisibleSettingPath: copilot_chat_visibility_setting_path(user_id: current_user&.display_login),
        ssoOrganizations: sso_organizations,
        apiVersion: copilot_api_version,
        **helpers.copilot_chat_payload(params[:scroll_copilot_to_top].present?, saml_authorized_organizations(cap_filter, user), request),
      }
    }
  end

  private

  def feature_enabled?
    true
  end

  sig { returns(T.nilable(String)) }
  def copilot_api_version
    if current_user&.feature_enabled?(:copilot_api_version_20250501)
      CopilotAPI::VERSION_2025_05_01
    else
      nil
    end
  end

  def render_popover?
    current_user&.feature_enabled?(:copilot_chat_new_user_popover) &&
    !current_user&.dismissed_notice?(:copilot_chat_new_user_popover)
  end

  memoize def current_repository
    return unless referring_params[:user_id] && referring_params[:repository]
    repo = Repository.with_name_with_owner(referring_params[:user_id], referring_params[:repository])
    cap_filter.authorized_resources(repo).first
  end

  memoize def tree_name
    if referring_params[:name].present?
      referring_params[:name].split("/").first
    else
      current_repository&.default_branch
    end
  end

  # current_repository is not required but used in the CAP filter if given
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
