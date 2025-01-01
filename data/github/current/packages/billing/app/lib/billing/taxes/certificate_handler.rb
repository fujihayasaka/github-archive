# typed: strict
# frozen_string_literal: true

module Billing
  module Taxes
    class CertificateHandler

      sig { returns(Customer) }
      attr_reader :customer

      sig { returns(Billing::Interfaces::RemoteFileStorage) }
      attr_reader :adapter

      sig { params(customer: Customer, adapter: Billing::Interfaces::RemoteFileStorage).void }
      def initialize(customer:, adapter: Billing::Taxes::CertificateStorageAzureAdapter.new)
        @customer = customer
        @adapter = adapter
      end

      sig { params(file: ActionDispatch::Http::UploadedFile).returns(String) }
      def new_file_identifier(file:)
        "customer:#{customer.id}:created_at:#{GitHub::Billing.now.to_i}" + File.extname(file.original_filename)
      end

      # An example file looks like this:
      # #<ActionDispatch: :Http: :UploadedFile: 0x00009fa1229b2ac2 @tempfile=#<Tempfile:/tmp/RackMultipart20240502-122134-162iik.pdf>,
      #   @content_type="application/pdf",
      #   @original_filename="monalisa-salestax-exemption.pdf",
      #   @headers="Content-Disposition: form-data; name=\"file\"; filename=\"monalisa-salestax-exemption.pdf\"\r\nContent-Type: application/pdf\r\n">,
      sig { params(file: ActionDispatch::Http::UploadedFile).returns(GitHub::Billing::Result) }
      def submit_certificate(file:)
        file_name = new_file_identifier(file:)
        metadata = {
          filename: file.original_filename,
          content_type: file.content_type
        }
        adapter.upload(file_name:, file: file.read, options: { metadata: metadata })

        if customer.tax_exemption_status.present?
          tax_exemption_status = T.must(customer.tax_exemption_status)
          # Once a customer uploads a new certificate, their old file is no longer needed
          adapter.delete(file_name: tax_exemption_status.certificate_name) if tax_exemption_status.certificate_name.present?
          # Once a customer uploads a new certificate, their tax exemption status is considered approved until proven otherwise
          tax_exemption_status.update!(status: Billing::TaxExemptionStatus.statuses[:approved], certificate_name: file_name)
        else
          tax_exemption_status = Billing::TaxExemptionStatus.create(customer_id: customer.id, certificate_name: file_name)
        end

        BillingNotificationsMailer.tax_exemption_certificate_uploaded(tax_exemption_status).deliver_later

        GitHub::Billing::Result.success
      end

      sig { returns(T.nilable(String)) }
      def download_certificate
        return if customer.tax_exemption_status&.certificate_name.nil?

        certificate_name = T.must(customer.tax_exemption_status).certificate_name
        adapter.download(file_name: certificate_name)
      end

      sig { params(expires_in: ActiveSupport::Duration).returns(T.nilable(String)) }
      def get_certificate_url(expires_in: 1.week)
        return if customer.tax_exemption_status&.certificate_name.nil?

        certificate_name = T.must(customer.tax_exemption_status).certificate_name
        adapter.get_url(file_name: certificate_name, expires_in: expires_in)
      end

      sig { params(reason: String).returns(GitHub::Billing::Result) }
      def reject_certificate(reason:)
        return GitHub::Billing::Result.failure "The customer does not have an existing tax exemption record" unless customer.tax_exemption_status.present?
        tax_exemption_status = T.must(customer.tax_exemption_status)

        fields = {
          status: :rejected,
          status_reason: reason,
          certificate_name: nil
        }
        tax_exemption_status.update!(**fields)

        GitHub::Billing::Result.success
      end
    end
  end
end
