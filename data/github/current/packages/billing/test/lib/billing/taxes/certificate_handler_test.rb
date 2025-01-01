# typed: true
# frozen_string_literal: true

require "test_helper"
require "azure/storage/common"
require "azure/storage/blob"

class Billing::Taxes::CertificateHandlerTest < GitHub::TestCase
  include ActionMailer::TestHelper

  setup do
    @customer = create(:customer)
    create(:organization, customer: @customer)
    @azure_blob_service = mock("::Azure::Storage::Blob::BlobService")
    @billing_azure_client = Billing::Azure::BlobClient.new(Billing::Azure::Storage.account_management_config)
    @billing_azure_client.stubs(:client).returns(@azure_blob_service)
    @adapter = Billing::Taxes::CertificateStorageAzureAdapter.new
    @adapter.stubs(:azure_blob_client).returns(@billing_azure_client)
    @certificate_handler = Billing::Taxes::CertificateHandler.new(customer: @customer, adapter: @adapter)
    @container = Billing::Taxes::CertificateStorageAzureAdapter::TAX_CERTIFICATES_AZURE_BLOB_CONTAINER

    @content_type = "application/pdf"
    @original_filename = "my_cert.pdf"
    @file = ActionDispatch::Http::UploadedFile.new({
      filename: @original_filename,
      type: @content_type,
      tempfile: File.open(file_fixture("billing/Common_Sales_and_Use_Tax_Exemptions.pdf"), "rb")
    })
  end

  context "#download_certificate" do
    test "downloads certificate" do
      mock_certificate_data = "certificate content"
      mock_url = "https://storage-account-name.blob.core.windows.net/container-name/testfilename?fdsfs23r2d&sp="
      Billing::Azure::SharedAccessSignatureUrlGenerator.expects(:generate_sas_url).returns(mock_url)
      Net::HTTP.expects(:get).with(URI.parse(mock_url)).returns(mock_certificate_data).once
      create(:tax_exemption_status, customer: @customer)

      assert_equal mock_certificate_data, @certificate_handler.download_certificate
    end
  end

  context "#submit_certificate" do
    test "sets metadata for the certificate if it's missing" do
      freeze_time do
        now = GitHub::Billing.now
        certificate_name = "customer:#{@customer.id}:created_at:#{now.to_i}.pdf"
        metadata = { filename: @original_filename, content_type: @content_type }

        blob = Azure::Storage::Blob::Blob.new
        @azure_blob_service.expects(:create_block_blob)
          .with(@container, certificate_name, @file.read, options: { metadata: metadata })
          .returns(blob)
          .once
        @azure_blob_service.expects(:set_blob_metadata)
          .with(@container, certificate_name, metadata)
          .returns(nil)
        @file.rewind

        @certificate_handler.submit_certificate(file: @file)
      end
    end

    test "uploads a certificate through the Billing::Azure::BlobClient" do
      freeze_time do
        now = GitHub::Billing.now
        certificate_name = "customer:#{@customer.id}:created_at:#{now.to_i}.pdf"
        metadata = { filename: @original_filename, content_type: @content_type }

        blob = Azure::Storage::Blob::Blob.new
        blob.metadata = metadata
        @azure_blob_service.expects(:create_block_blob)
          .with(@container, certificate_name, @file.read, options: { metadata: metadata })
          .returns(blob)
          .once
        @file.rewind

        @certificate_handler.submit_certificate(file: @file)
      end
    end

    test "sends email when submitting certificate" do
      freeze_time do
        blob = Azure::Storage::Blob::Blob.new
        blob.metadata = { filename: @original_filename, content_type: @content_type }
        @azure_blob_service.stubs(:create_block_blob).returns(blob)

        cert_url = "https:://azure.com/cert.pdf"
        Billing::Azure::SharedAccessSignatureUrlGenerator.stubs(:generate_sas_url).returns(cert_url)
        Net::HTTP.stubs(:get).returns("data")

        assert_emails 1 do # i.e. BillingNotificationsMailer.tax_exemption_certificate_uploaded
          @certificate_handler.submit_certificate(file: @file)
        end
      end
    end

    test "creates a new tax exemption status if one does not exist" do
      freeze_time do
        now = GitHub::Billing.now
        certificate_name = "customer:#{@customer.id}:created_at:#{now.to_i}.pdf"
        metadata = { filename: @original_filename, content_type: @content_type }

        blob = Azure::Storage::Blob::Blob.new
        blob.metadata = metadata
        @azure_blob_service.expects(:create_block_blob)
          .with(@container, certificate_name, @file.read, options: { metadata: metadata })
          .returns(blob)
          .once

        refute @customer.tax_exemption_status
        @file.rewind
        @certificate_handler.submit_certificate(file: @file)

        @customer.reload
        assert @customer.tax_exemption_status.present?
        assert @customer.tax_exemption_status.approved?
        assert @customer.tax_exemption_status.certificate_name.present?
      end
    end

    test "updates a rejected tax exemption when a certificate is uploaded and removes outdated certificate" do
      freeze_time do
        now = GitHub::Billing.now
        old_certificate_name = "customer:#{@customer.id}:created_at:long_ago.pdf"
        certificate_name = "customer:#{@customer.id}:created_at:#{now.to_i}.pdf"
        metadata = { filename: @original_filename, content_type: @content_type }

        blob = Azure::Storage::Blob::Blob.new
        blob.metadata = metadata
        @azure_blob_service.expects(:create_block_blob)
          .with(@container, certificate_name, @file.read, options: { metadata: metadata })
          .returns(blob)
          .once
        @azure_blob_service.expects(:delete_blob)
          .with(@container, old_certificate_name)
          .returns(Azure::Storage::Blob::Blob.new).once
        create(:tax_exemption_status, customer: @customer, certificate_name: old_certificate_name, status: :rejected, status_reason: "expired certificate")

        @file.rewind
        @certificate_handler.submit_certificate(file: @file)

        @customer.reload
        assert @customer.tax_exemption_status.approved?
      end
    end
  end

  context "#get_certificate_url" do
    test "generates an expiring url through the Billing::Azure::SharedAccessSignatureUrlGenerator" do
      freeze_time do
        now = GitHub::Billing.now
        certificate_name = "customer:#{@customer.id}:created_at:#{now.to_i}.pdf"
        expected_url = "https://storage-account-name.blob.core.windows.net/container-name/testfilename?fdsfs23r2d&sp="
        Billing::Azure::SharedAccessSignatureUrlGenerator.expects(:generate_sas_url).returns(expected_url)
        create(:tax_exemption_status, customer: @customer, certificate_name: certificate_name)

        url = @certificate_handler.get_certificate_url

        assert_equal url, expected_url
      end
    end
  end

  context "#reject_certificate" do
    test "sets the tax exemption status to :rejected" do
      create(:tax_exemption_status, customer: @customer)
      assert @customer.tax_exemption_status.approved?

      @certificate_handler.reject_certificate(reason: "wrong u.s. state")
      assert @customer.reload.tax_exemption_status.rejected?
    end

    test "does not delete the actual uploaded certificate file" do
      certificate_name = "monalisa-sales-exempt-cert.pdf"
      create(:tax_exemption_status, customer: @customer, certificate_name: certificate_name)
      @azure_blob_service.expects(:delete_blob)
        .with(@container, certificate_name, options: {})
        .returns(Azure::Storage::Blob::Blob.new)
        .never

      assert @customer.tax_exemption_status.approved?

      @certificate_handler.reject_certificate(reason: "wrong u.s. state")
      assert @customer.reload.tax_exemption_status.rejected?
    end
  end
end
