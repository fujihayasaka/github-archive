# typed: true
# frozen_string_literal: true

module Orgs
  class DeployKeysController < Controller
    before_action :organization_admin_required
    before_action :ensure_trade_restrictions_allows_org_settings_access

    depends_on_clusters \
      ApplicationRecord::Authnd,
      ApplicationRecord::Billing,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::Copilot,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      only: [:index]

    def index
      render_index
    end

    def update
      # Inherited only returns true if the org has a business with the policy set
      # When the policy is set on the business, the org cannot set the policy
      return render_404 if this_organization.deploy_key_policy_inherited?

      return head :bad_request unless params[:organization].present? && params[:organization][:deploy_key_policy].present?

      message = nil
      case params[:organization][:deploy_key_policy]
      when "enabled"
        this_organization.enable_deploy_key_policy(actor: current_user)
        message = "Deploy key policy enabled."
      when "disabled"
        this_organization.disable_deploy_key_policy(actor: current_user)
        message = "Deploy key policy disabled."
      else
        flash.now[:error] = "Could not update the deploy key policy. Please try again."
      end

      flash.now[:notice] = message
      render_index
    end

    private

    def render_index
      repository_ids = this_organization.repositories.pluck(:id)
      repositories_using_deploy_keys_count = PublicKey.where(repository_id: repository_ids).count
      render "orgs/deploy_keys/index", locals: {
        form_disabled: this_organization.deploy_key_policy_inherited?,
        repositories_using_deploy_keys_count: repositories_using_deploy_keys_count,
      }
    end
  end
end
