# typed: true
# frozen_string_literal: true

class Businesses::CopilotByokCustomModelOrganizationsController < Businesses::BusinessController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_copilot_enabled

  ORG_LIMIT = 100

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    only: [:index]

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index],
    optional: true

  def index
    orgs = load_orgs
    render json: orgs.map { |org| org_payload_data(org) }
  end

  private

  sig { params(org: Organization).returns(CopilotByok::Types::Organization) }
  def org_payload_data(org)
    {
      id: org.id,
      displayLogin: org.display_login,
      name: org.name,
      avatarUrl: org.primary_avatar_url,
    }
  end

  sig { returns T::Array[Organization] }
  def load_orgs
    query = params[:q]
    enabled_orgs = if query.present?
      []
    else
      CopilotByok::CustomModelPolicy.new(business: this_business).targeted_orgs_with_enabled_models
    end
    remaining_org_scope = this_business.organizations.by_login
    remaining_org_scope = remaining_org_scope.where.not(id: enabled_orgs) if enabled_orgs.any?
    remaining_org_scope = remaining_org_scope.with_substring("users.display_login", query) if query.present?
    # Even if the enterprise has enabled hundreds of orgs, still allow the user to search remaining orgs:
    remaining_org_limit = ORG_LIMIT - enabled_orgs.size
    remaining_org_limit = 1 if remaining_org_limit <= 1
    remaining_orgs = remaining_org_scope.limit(remaining_org_limit).to_a
    (enabled_orgs + remaining_orgs).sort_by { |org| org.display_login.downcase }
  end

  sig { returns(Copilot::Business) }
  memoize def copilot_business
    Copilot::Business.new(this_business)
  end

  sig { void }
  def ensure_copilot_enabled
    render_404 unless copilot_business.copilot_enabled?
  end
end
