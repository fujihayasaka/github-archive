# typed: true
# frozen_string_literal: true

class InsightsController < ApplicationController
  include InsightsHelper

  before_action :login_required
  before_action :check_organization_exist
  before_action :dotcom_required
  before_action :require_insights_enabled
  before_action :check_user_access

  FLAGS = [:insights_codeblocks].freeze
  preload_features FLAGS

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:insights_auth_and_config]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:insights_auth_and_config],
    optional: true

  def insights_auth_and_config # rubocop:todo GitHub/UseRestfulActions
    render json: auth_json, content_type: "application/json"
  end

  def auth_json # rubocop:todo GitHub/UseRestfulActions
    scope = markdown_embed_scope_for(this_organization)
    {
      token: markdown_embed_token_for(
        scope: scope,
        data: {
          repository_id: params[:repository_id],
          organization_id: params[:organization_id],
          source: request.referrer
        }
      ),
      authScope: scope,
      organization: this_organization.name
    }
  end

  def require_insights_enabled # rubocop:todo GitHub/UseRestfulActions
    return if FeatureFlag.vexi.enabled?(:insights_codeblocks, this_organization, default: false)
    return if FeatureFlag.vexi.enabled?(:insights_codeblocks, this_repository, default: false)
    return if FeatureFlag.vexi.enabled?(:memex_insights, this_organization, default: false)
    return if FeatureFlag.vexi.enabled?(:memex_insights, current_user, default: false)
    render_404
  end

  def check_user_access # rubocop:todo GitHub/UseRestfulActions
    return if this_organization&.member?(current_user)
    return if this_repository&.readable_by?(current_user)

    render_404
  end

  private def target_for_conditional_access
    this_organization || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def check_organization_exist # rubocop:todo GitHub/UseRestfulActions
    return if this_organization
    render_404
  end

  def this_organization # rubocop:todo GitHub/UseRestfulActions
    # consider the owner of repo if exists
    if this_repository
      return this_repository.owner if this_repository.owner.organization?
    end
    return unless params[:organization_id]
    @this_organization ||= Organization.find_by(id: params[:organization_id])
  end

  def this_repository # rubocop:todo GitHub/UseRestfulActions
    return unless params[:repository_id]
    @this_repository ||= if FeatureFlag.vexi.enabled?(:repos_domain_controllers, default: false)
      Repositories.domain.by_id(params[:repository_id].to_i)
    else
      Repository.find_by(id: params[:repository_id])
    end
  end

end
