# typed: strict
# frozen_string_literal: true

module Stafftools
  class ProductEnablementsController < StafftoolsController
    extend T::Sig
    include ApplicationController::VerifiedFetchDependency
    include ::Licensing::Licensify

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      only: [:index]

    allow_verified_fetch only: [:index, :create]

    sig { void }
    def index
      respond_to do |format|
        format.json do
          licensify_req = Licensify::Services::V1::GetProductEnablementsRequest.new(customerId: customer_id_param.to_i)
          licensify_res = licensify_client.get_product_enablements(licensify_req)
          if licensify_res.error.present?
            return render json: { error: licensify_res.error, productEnablements: [] }, status: :internal_server_error
          end
          render json: licensify_res.data, status: :ok
        end
      end
    rescue Faraday::Error => e
      Failbot.report(e)
      render json: { error: "Unable to query product enablements: #{e}", productEnablements: [] }, status: :internal_server_error
    end

    sig { void }
    def create
      licensify_req = Licensify::Services::V1::UpsertProductEnablementRequest.decode_json(request.body.read)
      licensify_res = licensify_client.upsert_product_enablement(licensify_req)
      if licensify_res.error.present?
        return render json: { error: licensify_res.error }, status: Twirp::ERROR_CODES_TO_HTTP_STATUS[licensify_res.error.code]
      end
      render json: {}, status: :ok
    rescue ArgumentError, Google::Protobuf::ParseError, JSON::ParserError => e
      render json: { error: "Invalid request body: #{e}" }, status: :bad_request
    rescue Faraday::Error => e
      Failbot.report(e)
      render json: { error: "Unable to save product enablement: #{e}" }, status: :internal_server_error
    end

    private

    sig { returns(String) }
    def customer_id_param
      params.require(:customer_id)
    end
  end
end
