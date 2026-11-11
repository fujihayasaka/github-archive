# typed: strict
# frozen_string_literal: true

class Repos::CodeScanning::AvailableAssigneesController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include CodeScanning::AlertsSerializer
  include CodeScanning::ControllerAccessChecks

  before_action :check_code_scanning_write

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Spokes,
    only: [:index]

  sig { void }
  def index
    # First retrieve all users that can be assigned to alerts. We will later filter this down to users that also have
    # code scanning write access.
    ids = current_repository.available_assignee_ids(limit: 10_000)

    includes_associations = []
    includes_associations << :business_user_accounts if GitHub.multi_tenant_enterprise?

    tenant_id = GitHub::CurrentTenant.get.try(:id) || User::MultiTenantEnterpriseManagedDependency::NON_ENTERPRISE_MANAGED_BUSINESS_ID
    scope = User.where(id: ids, business_id: tenant_id).includes(includes_associations)
    scope = scope.order("display_login").filter_spam_for(current_user)

    query = params[:query].to_s.strip

    if query.present?
      scope = scope.like_display_login_or_profile_name(query)
    end

    # We are limiting to 1,000 users here to avoid performance issues when checking authorization. It's possible that
    # we end up with less than 1,000 users (or even zero users) if many users don't have code scanning write access.
    # However, that is unlikely since available_assignee_ids mostly includes users that have write access, which
    # implies that they also have code scanning write access.
    scope = scope.limit(1000)

    # Filter to users with code scanning write access.
    users = CodeScanning::RepositoryPermissions.new(current_repository).filter_code_scanning_writable_by(scope)

    # If the Copilot SWE agent is enabled, we need to add it to the list of
    # available assignees. This could include all globally assignable apps, or
    # all apps that are installed and assignable in the repository - but as we're
    # specifically checking for copilot_swe_agent_enabled?, we should only include that one.
    # This is based on https://github.com/github/github/blob/d25913df950c9a647307878a807dfd5200596fce/app/platform/helpers/assignees_helper.rb#L33
    # and https://github.com/github/github/blob/10b261136f672374f7c9097d4476e149ec26d9a5/app/platform/loaders/integration_installation/repository_for_viewer.rb#L17
    if current_repository.writable_by?(current_user) && current_repository.copilot_swe_agent_enabled?(current_user)
      integration = ::Apps::Privileged.integration(:copilot_swe_agent)

      if query.blank? || integration.name.downcase.include?(query.downcase) || integration.slug.downcase.include?(query.downcase)
        users << integration.bot
      end

      users.uniq
    end

    render json: {
      users: users.map do |user|
        serialized_assignee(user)
      end
    }
  end
end
