# typed: strict
# frozen_string_literal: true

module Billing
  class MeteredUsageExport < ApplicationRecord::Domain::Billing
    USAGE_REPORT_AZURE_BLOB_CONTAINER = "billing-metered-exports-reports"
    MS_VERSION = "2021-12-02"

    extend T::Sig
    include UrlHelpers

    belongs_to :requester, class_name: "User", optional: true
    belongs_to :billable_owner, polymorphic: true, optional: false

    validates :starts_on, presence: true
    validates :ends_on, presence: true
    validates :filename, presence: true, uniqueness: { case_sensitive: false }

    sig { returns(String) }
    def generate_expiring_url
      if is_azure_blob_storage
        Billing::Azure::SharedAccessSignatureUrlGenerator.generate_sas_url(
          storage_config: Billing::Azure::Storage.metered_billing_config,
          blob_container: USAGE_REPORT_AZURE_BLOB_CONTAINER,
          file_name: filename,
          expires_in: 60.minutes,
          content_type: "text/csv"
        )
      else
        presigner.presigned_url(
          :get_object,
          bucket: GitHub.s3_metered_exports_bucket,
          key: filename,
          expires_in: 60.minutes.to_i,
        )
      end
    end

    sig { returns(String) }
    def get_url
      if billable_owner.is_a?(Business)
        if is_azure_blob_storage
          if requester&.employee? && requester&.site_admin?
            GitHub.stafftools_url + stafftools_enterprise_billing_usage_report_path(billable_owner, self)
          else
            GitHub.url + enterprise_billing_usage_report_path(billable_owner, self)
          end
        else
          GitHub.url + metered_export_enterprise_path(billable_owner, self)
        end
      elsif billable_owner.organization?
        GitHub.url + org_metered_export_path(billable_owner, self)
      else
        GitHub.url + metered_export_path(self)
      end
    end

    private

    sig { returns(Aws::S3::Presigner) }
    def presigner
      @presigner ||= T.let(Aws::S3::Presigner.new(
        client: GitHub.s3_metered_exports_client,
      ), T.nilable(Aws::S3::Presigner))
    end
  end
end
