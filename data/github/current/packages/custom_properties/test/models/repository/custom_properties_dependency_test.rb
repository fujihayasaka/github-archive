# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCustomPropertiesDependencyTest < GitHub::TestCase
  fixtures do
    @admin = create :user
    @org = create :enterprise_linked_organization, admin: @admin
    @org_repo = create :repository, owner: @org

    @env_definition = create :custom_property_definition, source: @org, property_name: "env"
    create :custom_property_value, definition: @env_definition, target: @org_repo, value: "prod"
  end

  context "#custom_properties_values" do
    test "returns a hash of custom properties for a org repo" do
      properties = @org_repo.custom_properties_values

      assert properties.count, 1

      property = properties.first
      assert_equal property.definition, @env_definition
      assert_equal property.property_name, "env"
      assert_equal property.manual_value, "prod"
      assert_equal property.effective_value, "prod"
    end

    test "returns empty for a non_org" do
      repo = create :repository
      assert_nil repo.custom_properties_values
    end

    test "can be batch for multiple repos" do
      org_repo_2 = create :repository, owner: @org
      org_repo_3 = create :repository, owner: @org
      non_org_repo = create :repository

      create :custom_property_value, target: org_repo_2, definition: @env_definition, value: "test"
      create :custom_property_value, target: org_repo_3, definition: @env_definition, value: "test"

      assert_query_count_per_table({ custom_property_values: 1, custom_property_definitions: 2 }) do
        GitHub::PrefillAssociations.prefill_batch_method([@org_repo, org_repo_2, non_org_repo], :custom_properties_values)
      end

      assert_query_count_per_table({ custom_property_values: 0, custom_property_definitions: 0 }) do
        @org_repo.custom_properties_values
        org_repo_2.custom_properties_values
        non_org_repo.custom_properties_values
      end

      assert_query_count_per_table({ custom_property_values: 1, custom_property_definitions: 2 }) do
        org_repo_3.custom_properties_values
      end
    end

    test "a non-org repo won't trigger any query" do
      repo = create :repository

      assert_query_count_per_table({ custom_property_values: 0, custom_property_definitions: 0 }) do
        GitHub::PrefillAssociations.prefill_batch_method([repo], :custom_properties_values)
      end

      assert_query_count_per_table({ custom_property_values: 0, custom_property_definitions: 0 }) do
        repo.custom_properties_values
      end
    end

    test "a repo without owner won't load any properties" do
      repo = create :repository
      repo.owner.destroy!
      repo.reload

      GitHub::PrefillAssociations.prefill_batch_method([repo], :custom_properties_values)

      assert_nil repo.custom_properties_values
    end
  end
end
