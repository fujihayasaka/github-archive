# typed: true
# frozen_string_literal: true

require "hydro/publisher"

class Stafftools::Billing::ReconcileOrgTransferUsagesController < StafftoolsController
  include Hydro
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Stafftools::Billing::ReconcileOrgTransferUsagesController#create",
  ]
  before_action :dotcom_required
  before_action :try_parse_json_params, only: [:create]
  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::Mysql5,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Billing,
  ApplicationRecord::Ballast,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Repositories,
  ApplicationRecord::Configurations,
  only: [:index, :create]


  allow_verified_fetch only: [:create]

  def self.react_bundle_name
    "billing-app"
  end

  def index
    render_react_app(
      payload: { orgs: "org1" },
      title: "Reconcile Org Transfer Usages",
      layout: "layouts/stafftools/react_stafftools",
    )
  end

  def create
    organization_id = params[:organizationId].to_i
    source_enterprise_customer_id = params[:sourceEnterpriseCustomerId].to_i
    destination_enterprise_customer_id = params[:destinationEnterpriseCustomerId].to_i
    organization = Organization.find_by id: organization_id
    unless organization && organization.feature_flag_enabled?(:billing_org_ownership_change_events, default: true)
      return render json: { error: "Organization not found or feature not enabled" }, status: :unprocessable_entity
    end

    source_enterprise = Customer.find_by id: source_enterprise_customer_id
    destination_enterprise = Customer.find_by id: destination_enterprise_customer_id
    unless source_enterprise.present? && destination_enterprise.present?
      render json: { error: "Source or destination enterprise customer not found" }, status: :unprocessable_entity and return
    end

    repo_ids = organization.repositories.pluck(:id)
    repos = Repository.includes(:internal_repository)
                     .select(:id, :source_id, :public)
                     .where(id: repo_ids)

    repository_info = repos.map do |repo|
      visibility = case repo.visibility.to_sym
      when :public
        Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility.lookup(
          Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility::PUBLIC
        )
      when :private
        Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility.lookup(
          Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility::PRIVATE
        )
      when :internal
        Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility.lookup(
          Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility::INTERNAL
        )
      else
        GitHub.logger.info(
          "billing_repo_visibility: Unexpected unknown repository visibility",
          "gh.repo.visibility" => repo.visibility.to_sym,
          "gh.repo.id" => repo.id,
        )
        Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility.lookup(
          Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility::VISIBILITY_UNKNOWN
        )
      end

      {
        id: repo.id,
        visibility: visibility,
      }
    end

    message = {
      organization_id: organization_id,
      actor_id: current_user.id,
      source_customer_id: source_enterprise_customer_id,
      destination_customer_id: destination_enterprise_customer_id,
      completed_at:  Time.now.utc.to_i,
      repositories: repository_info,
    }
    Hydro::PublishRetrier.publish(message, schema: "billingplatform.v1.OrgOwnershipChange")
    Rails.logger.info("Stafftools::Billing::ReconcileOrgTransferUsagesController published message: #{message.inspect}")
    head :ok
  end
end
