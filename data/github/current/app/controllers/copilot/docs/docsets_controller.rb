# typed: true
# frozen_string_literal: true

class Copilot::Docs::DocsetsController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CopilotForDocsHelper
  include CopilotChatHelper
  include ReactHelper

  depends_on_clusters(
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    only: [:index],
  )

  before_action :require_logged_in_user
  before_action :require_feature_enabled
  allow_verified_fetch only: [:index]

  @react_bundle_name = "copilot-for-docs"

  # This endpoint is used by the dotcom chat react frontend.
  def index
    render json: {
      knowledgeBases: knowledge_bases,
      # If the knowledge bases are empty the frontend will use this list of orgs to show a button or dropdown so admins
      # can create a knowledge base
      administratedCopilotEnterpriseOrganizations: orgs,
    }
  rescue CopilotAPI::UnauthorizedError
    render_404
  end

  private

  memoize def knowledge_bases
    resp = current_user_copilot_api.list_knowledge_bases
    kbs = resp[:kbs] || []

    populate_avatars(kbs)
    kbs = filter_visible_docsets(kbs).map { |d| secure_and_decorate_docset(d) }
    remove_unviewable_knowledge_bases(kbs)
  end

  # Looking up a list of administrated orgs can be expensive so let's only do it if the knowledge bases are empty since
  # we only show the list of orgs if there aren't any knowledge bases.
  #
  # See perf/bug issue: https://github.com/github/copilot-core-productivity/issues/1443#issuecomment-2012956749
  def orgs
    if knowledge_bases.empty?
      administrated_copilot_enterprise_organizations(T.must(current_user))
    end
  end

  def populate_avatars(docsets)
    map = {}
    docsets.each do |docset|
      owner_id = docset[:ownerID]
      case docset[:ownerType]
      when "organization"
        org = Organization.find_by(id: owner_id)
        map[owner_id] = org&.primary_avatar_url
      when "user"
        user = User.find_by(id: owner_id)
        map[owner_id] = user&.primary_avatar_url
      end

      docset["avatarUrl"] = map[owner_id]
    end
  end

  # NOTE: we have a `login_required` method available to all controllers
  # that redirects to /login if the user is not logged in but
  # we want to render a 404 to avoid leaking any info about the feature
  def require_logged_in_user
    render_404 unless logged_in?
  end

  def require_feature_enabled
    render_404 unless copilot_chat_enabled_for_current_user?
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  sig { returns Copilot::User::CopilotApi }
  def current_user_copilot_api
    token = T.must(current_user).feature_enabled?(:"copilot-kb-migration") ? nil : GitHub.decode_and_decrypt_capi_token(request&.headers[CopilotAPI::TOKEN_HEADER])

    T.must(current_user).copilot_api(
      integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID,
      session: user_session,
      real_ip: request&.remote_ip,
      token:,
    )
  end
end
