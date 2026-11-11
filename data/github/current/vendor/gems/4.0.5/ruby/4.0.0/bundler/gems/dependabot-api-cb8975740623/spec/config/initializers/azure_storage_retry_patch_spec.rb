# frozen_string_literal: true

require "rails_helper"
require "active_storage/service/azure_storage_service"

RSpec.describe AzureStorageRetryPatch do
  let(:service) do
    ActiveStorage::Service::AzureStorageService.new(
      storage_account_name: "test_account",
      storage_access_key: "test_key",
      container: "test_container"
    )
  end

  let(:client) { instance_double(Azure::Storage::Blob::BlobService) }

  before do
    # Mock the client creation inside AzureStorageService
    allow(Azure::Storage::Blob::BlobService).to receive(:create).and_return(client)
    allow(client).to receive(:client).and_return(instance_double(Azure::Storage::Common::Client))
    allow(client).to receive(:with_filter)
  end

  context "when dependabot_abs_retries feature flag is enabled" do
    before do
      stub_monolith_feature(:dependabot_abs_retries, actor: nil, enabled: true)
    end

    it "adds the DependabotAzureRetryFilter" do
      service
      expect(client).to have_received(:with_filter).with(instance_of(DependabotAzureRetryFilter))
    end
  end

  context "when dependabot_abs_retries feature flag is disabled" do
    before do
      stub_monolith_feature(:dependabot_abs_retries, actor: nil, enabled: false)
    end

    it "does not add the DependabotAzureRetryFilter" do
      service
      expect(client).not_to have_received(:with_filter)
    end
  end
end
