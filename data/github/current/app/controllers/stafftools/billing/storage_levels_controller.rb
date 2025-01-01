# typed: true
# frozen_string_literal: true

require "github/media_blob"

module Stafftools
  module Billing
    class StorageLevelsController < StafftoolsController
      include Stafftools::Billing::BillingPlatformHelper

      before_action :dotcom_required

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
        only: [:index]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:index],
        optional: true

      def index
        if request_params_present?
          client = ::Billing::Platform::Api::Client.new

          response = client.get_watermark_level(
            usage_entity_id: params[:customer_id].to_s,
            sku: params[:sku].to_s,
            org_id: params[:org_id].presence.to_i,
            repo_id: params[:repo_id].presence.to_i,
          )

          lfs_usage = nil
          if params[:sku] == "git_lfs_storage"
            network_id = ::Repositories::Public.get_active_or_deleted!(params[:repo_id].to_i).network_id
            # `.query_owner_network_storage` processes a batch of repository networks
            # it expects the last network ID from the previous batch and the size of the next batch
            # so to process a single network, we pass network_id - 1 so the next batch starts from network_id
            lfs_usage = GitHub::MediaBlob.query_owner_network_storage(network_id - 1, 1).first.first
            lfs_usage = lfs_usage ? (lfs_usage[:size_in_gb] || 0) : 0
          end

          error = false
          if response.is_a?(::Billing::Platform::Api::Error)
            error = true
            flash.now[:error] = "An error happened while getting the storage levels"
          end

          render "stafftools/billing/storage_levels/index", locals: {
            storage_skus: fetch_watermark_pricings,
            error: error,
            billed_storage: response[:quantity],
            lfs_usage: lfs_usage,
          }
        else
          render "stafftools/billing/storage_levels/index", locals: {
            storage_skus: fetch_watermark_pricings,
            error: false,
            billed_storage: nil,
            lfs_usage: nil,
          }
        end
      end

      private

      def request_params_present?
        params[:customer_id].present? &&
           params[:sku].present? &&
           params[:org_id].present? &&
           params[:repo_id].presence.to_i > 0
      end

      def fetch_watermark_pricings
        pricings_list = stafftools_fetch_pricing
        pricings_list.select { |p| p[:meterType] == :PerHourUnitCharge }
      end
    end
  end
end
