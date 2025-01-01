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

        product = if params[:product] == "ghas"
          Licensify::Services::V1::Product::PRODUCT_GHAS
        else
          Licensify::Services::V1::Product::PRODUCT_SDLC
        end

        licensify_req = Licensify::Services::V1::GetLicenseeGlobalIdsRequest.new(
          customerId: customer_id,
          product: product,
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

        #
        ids_by_model["Enterprise-Server-User"][:ids].each do |id|
          global_id = ids_by_model["Enterprise-Server-User"][:global_ids][id.to_s]
          server_user_id = global_id.split("/").last
          response_data << {
            type: "enterpriseServerUser",
            id: id,
            global_id: global_id,
            display_name: server_user_id + " (server-only)"
          }
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
        when "enterpriseServerUser"
          "gid://git-hub/Enterprise-Server-User/" + params[:id]
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
        sync_customer_request = Licensify::Services::V1::SyncCustomerRequest.new(
          customerId: customer_id,
        )

        sync_customer_response = licensify_client.sync_customer(sync_customer_request)

        if sync_customer_response.error.present?
          flash[:error] = "There was an issue synchronizing SDLC licenses - #{sync_customer_response.error}"
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
