# typed: true
# frozen_string_literal: true

require "test_helper"

module ContainerRegistry
  class ContainerRegistryTwirpTest < GitHub::TestCase
    test "#container_registry_client" do
      assert ContainerRegistry::Twirp.container_registry_client.is_a?(ContainerRegistry::Twirp::ContainerRegistryClient)
    end
  end
end
