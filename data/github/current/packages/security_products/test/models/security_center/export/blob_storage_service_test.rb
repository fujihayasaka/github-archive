# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Export
    class BlobStorageServiceTest < GitHub::TestCase
      fixtures do
        @org = create(:organization)
      end

      context ".get" do
        test "returns Azure service" do
          assert BlobStorageService.get.instance_of? AzureBlobStorageService
        end
      end
    end
  end
end
