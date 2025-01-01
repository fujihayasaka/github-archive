# typed: strict
# frozen_string_literal: true

class FilterProviders::BusinessOrganizationsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required

  include FilterProviders::Helpers::OrganizationSuggestionsPayloadHelper

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
  only: [:index, :show]

  ORGS_LIMIT = 30

  sig { void }
  def index
    orgs = business_organizations(params[:q])
      .limit(ORGS_LIMIT)
      .to_a

    render json: organization_suggestions_payload(orgs)
  end

  sig { void }
  def show
    org = business_organizations.find_by(login: params[:q])
    if org
      return render json: organization_payload(org)
    end

    head :unprocessable_entity
  end

  private

  sig { params(query: T.nilable(String)).returns(ActiveRecord::Relation) }
  def business_organizations(query = nil)
    T.cast(this_business, Business)
      .filtered_organizations(viewer: current_user, query:)
  end
end
