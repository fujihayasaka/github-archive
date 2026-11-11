# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateConfigsService::V1::UpdateConfigSerializer,
               type: :serializer do
  describe "#package_ecosystem" do
    let(:update_config) do
      FactoryBot.build(:update_config, package_manager: package_manager)
    end

    let(:serializer) do
      described_class.new(update_config)
    end

    let(:update_config_wrapper) do
      DependabotApi::V1::UpdateConfig.new(serializer.to_h)
    end

    # This test guards against a new package manager being added that cannot
    # be serialized by Twirp without a change to the protobuf.
    #
    # If this test fails, you will need to add the new value to
    # Twirp and bump the gem in both the service and client(s) before
    # the new value can be permitted in the database.
    PackageManagers::ALL.each do |key|
      context "with '#{key}'" do
        let(:package_manager) { key }

        let(:expected_value) do
          ParseConfigFile.
            token_for(package_manager: package_manager).
            underscore.
            upcase.
            to_sym
        end

        it "serializes the name correctly" do
          expect(update_config_wrapper.package_ecosystem.name).
            to eql(expected_value)
        end
      end
    end

    context "with an invalid package manager" do
      let(:update_config) do
        FactoryBot.build(:update_config, package_manager: "fedex")
      end

      before do
        allow(ParseConfigFile).
          to receive(:token_for).and_return("fedex")
      end

      it "raises an exception" do
        expect { update_config_wrapper }.
          to raise_error(RangeError,
                         "Unknown symbol value for enum field 'name'.")
      end
    end
  end
end
