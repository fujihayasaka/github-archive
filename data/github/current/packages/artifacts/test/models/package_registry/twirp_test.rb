# typed: true
# frozen_string_literal: true

require "test_helper"
require "proto-registry-metadata-api"

module PackageRegistry
  class PackageRegistryTwirpTest < GitHub::TestCase
    test "#metadata_client" do
      assert PackageRegistry::Twirp.metadata_client.is_a?(PackageRegistry::Twirp::MetadataClient)
    end

    test "#action_packages_client" do
      assert PackageRegistry::Twirp.action_packages_client.is_a?(PackageRegistry::Twirp::ActionPackages::Client)
    end
  end
end
