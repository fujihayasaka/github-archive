# frozen_string_literal: true

require "rails_helper"

# TODO: Currently this test is for only Proxima environment
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Azure Blob Storage integration", :proxima do
  let(:blob_key) { "azure_blob/blob-test.txt" }
  let(:blob_data) { File.read(Rails.root.join("spec/fixtures/files/azure-blob-entires/blob-test.txt")) }

  it "uploads a file to Azure Blob Storage and downloads it using Active Storage" do
    VCR.use_cassette("azure_blob/active_storage_integration") do
      blob_key = "azure_blob/blob-test.txt"
      blob_data = File.read(Rails.root.join("spec/fixtures/files/azure-blob-entires/blob-test.txt"))

      # Upload the fixture file to Azure Blob Storage
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(blob_data),
        filename: File.basename(blob_key),
        content_type: "text/plain",
        key: blob_key,
        service_name: :azure
      )

      # Download the file using Active Storage
      blob = ActiveStorage::Blob.find_by(key: blob_key)

      expect(blob).not_to be_nil
      expect(blob.download).to eq(blob_data)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
