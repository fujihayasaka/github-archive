# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateConfigsService::V1::PackageEcosystemSerializer,
               type: :serializer do
  describe "#repository_access_supported?" do
    package_managers_with_repository_access =
      PackageManagers::ALL -
      UpdateConfig::PACKAGE_MANAGERS_WITH_CODE_EXECUTION

    package_managers_with_repository_access.each do |pm|
      it "returns true for #{pm}" do
        serializer = described_class.new(pm)
        expect(serializer).to be_repository_access_supported
      end
    end

    UpdateConfig::PACKAGE_MANAGERS_WITH_CODE_EXECUTION.each do |pm|
      it "returns false for #{pm}" do
        serializer = described_class.new(pm)
        expect(serializer).not_to be_repository_access_supported
      end
    end
  end
end
