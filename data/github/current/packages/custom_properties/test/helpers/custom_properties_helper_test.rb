# typed: strict
# frozen_string_literal: true

require "test_helper"

class CustomPropertiesHelperTest < GitHub::TestCase
  include CustomPropertiesHelper

  context "repo_custom_properties_hash" do
    test "return nil if repo is not part of an org" do
      repo = create :repository
      assert_nil repo_custom_properties_hash(repo)
    end

    test "return effective properties for repo, nils are stripped" do
      org = create :organization
      repo = create :repository, owner: org

      # Definition without values or a default. Must not be in the result.
      create :custom_property_definition, source: org, property_name: "team"

      env_definition = create :custom_property_definition, source: org, property_name: "env"
      create :custom_property_value, definition: env_definition, target: repo, value: "prod"

      create :custom_property_definition, source: org, property_name: "language", required: true, default_value: "ruby"

      platform_definition = create :custom_property_definition, :multi_select, source: org
      create :custom_property_value, definition: platform_definition, target: repo, value: "ios"
      create :custom_property_value, definition: platform_definition, target: repo, value: "web"

      legacy_definition = create :custom_property_definition, :true_false, source: org
      create :custom_property_value, definition: legacy_definition, target: repo, value: "true"

      assert_equal repo_custom_properties_hash(repo), { env: "prod", language: "ruby", platform: %w(ios web), is_legacy: "true" }
    end
  end
end
