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
        response_data = ids_by_type_response_data(license_status, enablement_reason)
        render json: response_data, status: :ok
      end

      sig { void }
      def show
        type = case params[:type]
        when "user"
          Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_USER
        when "enterpriseServerUser"
          Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_ENTERPRISE_SERVER_USER
        else
          Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_UNSPECIFIED
        end

        return render json: { error: "Invalid licensee type" }, status: :internal_server_error if type == Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_UNSPECIFIED

        licensify_req = Licensify::Services::V1::GetCustomerLicenseRequest.new(
          customerId: customer_id,
          licensee: Licensify::Services::V1::Licensee.new(
            type:,
            id: params[:id],
          ),
          products: [licensify_product],
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

      sig { returns(Integer) }
      def license_status
        license_status_param = params[:license_status]&.to_sym || :LICENSE_STATUS_UNSPECIFIED
        Licensify::Services::V1::LicenseStatus.resolve(license_status_param) ||
          Licensify::Services::V1::LicenseStatus::LICENSE_STATUS_UNSPECIFIED
      end

      sig { returns(Integer) }
      def enablement_reason
        enablement_reason_param = params[:enablement_reason]&.to_sym || :ENABLEMENT_REASON_UNSPECIFIED
        Licensify::Services::V1::EnablementReason.resolve(enablement_reason_param) ||
          Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_UNSPECIFIED
      end

      sig { returns(Integer) }
      memoize def licensify_product
        product_mapping = {
          "ghas" => Licensify::Services::V1::Product::PRODUCT_GHAS,
          "code_security" => Licensify::Services::V1::Product::PRODUCT_CODE_SECURITY,
          "secret_protection" => Licensify::Services::V1::Product::PRODUCT_SECRET_PROTECTION,
          "sdlc" => Licensify::Services::V1::Product::PRODUCT_SDLC
        }
        product_mapping.fetch(params[:product], Licensify::Services::V1::Product::PRODUCT_UNSPECIFIED)
      end


      sig { params(license_status: Integer, enablement_reason: Integer).returns(T::Array[T::Hash[String, T.untyped]]) }
      def ids_by_type_response_data(license_status, enablement_reason)

        license_statuses = if license_status == Licensify::Services::V1::LicenseStatus::LICENSE_STATUS_UNSPECIFIED
          []
        else
          [license_status]
        end

        enablement_reasons = if enablement_reason == Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_UNSPECIFIED
          []
        else
          [enablement_reason]
        end

        licensify_req = Licensify::Services::V1::GetLicenseeIdsByTypeRequest.new(
          customerId: customer_id,
          product: licensify_product,
          licenseStatuses: license_statuses,
          enablementReasons: enablement_reasons,
        )

        begin
          licensify_res = T.let(licensify_client.get_licensee_ids_by_type(licensify_req), Twirp::ClientResp[Licensify::Services::V1::GetLicenseeIdsByTypeResponse])
        rescue StandardError => e
          return render json: { error: "Failed to retrieve licensee IDs by type: #{e.message}" }, status: :internal_server_error
        end

        if licensify_res.error.present?
          return render json: { error: licensify_res.error }, status: :internal_server_error
        end

        licensify_licensee_ids_by_type = licensify_res.data.licenseeIdsByType

        user_ids = T.let([], T::Array[Integer])
        server_user_ids = T.let([], T::Array[String])

        licensify_licensee_ids_by_type.each do |group|
          group = T.let(group, Licensify::Services::V1::LicenseeIdsByType)

          type = case group.type
          when Symbol
            Licensify::Services::V1::LicenseeType.resolve(T.cast(group.type, Symbol))
          else
            T.cast(group.type, Integer)
          end

          user_ids = user_ids.concat(group.licenseeIds.map(&:to_i)) if type == Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_USER
          server_user_ids = server_user_ids.concat(group.licenseeIds.to_a) if type == Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_ENTERPRISE_SERVER_USER
        end

        response_data = ActiveRecord::Base.connected_to(role: :reading) do
          ::User.batched_scope(:id, values: user_ids, batch_size: 5000).execute do |scope|
            [scope.select(:id, :login).load_async]
          end.flatten.map do |user|
            {
              type: "user",
              id: user.id,
              global_id: user.to_global_id.to_s,
              display_name: user.login,
              avatar_url: user.primary_avatar_url,
            }
          end.sort_by { |lh| lh[:display_name] }
        end

        server_user_ids.each do |id|
          global_id = "gid://git-hub/Enterprise-Server-User/" + id.to_s
          server_user_id = global_id.split("/").last
          response_data << {
            type: "enterpriseServerUser",
            id: id,
            global_id: global_id,
            display_name: "#{id} (server-only)"
          }
        end

        response_data
      end
    end
  end
end
