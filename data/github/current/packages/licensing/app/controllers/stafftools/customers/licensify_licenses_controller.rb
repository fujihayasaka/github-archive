# typed: strict
# frozen_string_literal: true

module Stafftools
  module Customers
    class LicensifyLicensesController < StafftoolsController
      include ApplicationController::VerifiedFetchDependency
      include ::Licensing::Licensify

      before_action :dotcom_required
      before_action :customer_required

      sig { void }
      def index
        license_status = Licensify::Services::V1::LicenseStatus.resolve(params[:license_status].to_sym) ||
          Licensify::Services::V1::LicenseStatus::LICENSE_STATUS_UNSPECIFIED

        licensify_req = Licensify::Services::V1::GetLicenseeGlobalIdsRequest.new(
          customerId: customer_id,
          product: Licensify::Services::V1::Product::PRODUCT_SDLC,
          licenseStatus: license_status,
        )
        licensify_res = licensify_client.get_licensee_global_ids(licensify_req)
        if licensify_res.error.present?
          return render json: { error: licensify_res.error }, status: :internal_server_error
        end

        global_ids = licensify_res.data["globalIds"].map { |gid| GlobalID.parse(gid) }

        ids_by_model = Hash.new do |hash, key|
          hash[key] = {
            ids: [],
            global_ids: {}
          }
        end

        global_ids.each do |gid|
          ids_by_model[gid.model_name][:ids] << gid.model_id
          ids_by_model[gid.model_name][:global_ids][gid.model_id] = gid.to_s
        end

        response_data = ActiveRecord::Base.connected_to(role: :reading) do
          ::User.batched_scope(:id, values: ids_by_model["User"][:ids], batch_size: 5000).execute do |scope|
            [scope.select(:id, :login).load_async]
          end.flatten.map do |user|
            {
              type: "user",
              id: user.id,
              global_id: ids_by_model["User"][:global_ids][user.id.to_s],
              display_name: user.login,
              avatar_url: user.primary_avatar_url,
            }
          end.sort_by { |lh| lh[:display_name] }
        end

        render json: response_data, status: :ok
      end

      sig { void }
      def show
        global_id = case params[:type]
        when "user"
          ::User.new(id: params[:id]).to_global_id.to_s
        when "bua"
          ::BusinessUserAccount.new(id: params[:id]).to_global_id.to_s
        end

        render json: { error: "Invalid licensee type" }, status: :internal_server_error if global_id.nil?

        licensify_req = Licensify::Services::V1::GetCustomerLicenseRequest.new(
          customerId: customer_id,
          licensee: {
            globalId: global_id
          }
        )
        licensify_res = licensify_client.get_customer_license(licensify_req)
        if licensify_res.error.present?
          return render json: { error: licensify_res.error }, status: :internal_server_error
        end
        render json: licensify_res.data, status: :ok
      end

      sig { void }
      def sync_licenses # rubocop:todo GitHub/UseRestfulActions
        sync_org_memberships_req = Licensify::Services::V1::SyncOrganizationMembershipsRequest.new(
          entityId: customer_id,
          entityType: Licensify::Services::V1::SyncEntityType::SYNC_ENTITY_TYPE_CUSTOMER,
        )
        sync_org_memberships_res = licensify_client.sync_organization_memberships(sync_org_memberships_req)
        if sync_org_memberships_res.error.present?
          flash[:error] = "There was an issue synchronizing SDLC licenses - #{sync_org_memberships_res.error}"
        else
          flash[:notice] = "We're synchronizing your SDLC licenses. This may take a few minutes."
        end

        redirect_to :back
      end

      sig { void }
      def sync_customer # rubocop:todo GitHub/UseRestfulActions
        UpdateCustomerInLicensifyJob.perform_later(customer_id)

        flash[:notice] = "Enqueued job to synchronize customer to Licensify"
        redirect_to :back
      end

      private

      sig { returns(Integer) }
      memoize def customer_id
        params.require(:customer_id).to_i
      end

      sig { void }
      def customer_required
        unless customer_id.positive?
          render json: { error: "No customer found" }, status: :not_found
        end
      end
    end
  end
end
