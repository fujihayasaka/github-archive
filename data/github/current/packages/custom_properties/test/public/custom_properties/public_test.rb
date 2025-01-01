# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomProperties::PublicTest < GitHub::TestCase
  include PerformanceTestHelpers
  include CustomPropertiesTestHelper

  include CustomProperties
  include CustomProperties::Errors

  setup do
    @business = create :business
    @org = create :organization, name: "main-org", business: @business
    @repo = create :repository, owner: @org, name: "main-repo"

    @definition_env = create :custom_property_definition, source: @org, property_name: "environment"
    @definition_security = create :custom_property_definition, source: @org, property_name: "security"
    @biz_definition_version = create :custom_property_definition, source: @business, property_name: "biz_version", required: true, default_value: "0.0.1"
  end

  # the two authzd calls in this method are tested on their own, so this test is slim
  context "user_edit_permissions" do
    test "returns true for org admin and repo admin" do
      expected_count = 1
      assert_authzd_calls(single: 0, batch: expected_count) do
        permissions = Public.user_edit_permissions(@org.admins.first, @repo)
        assert permissions.org
        assert permissions.repo
      end

      user = create :user
      @repo.add_member(user, action: :admin)
      assert_authzd_calls(single: 0, batch: expected_count) do
        perms = Public.user_edit_permissions(user, @repo)
        refute perms.org
        assert perms.repo
      end
    end

    test "returns false for random user" do
      expected_count = 1
      assert_authzd_calls(single: 0, batch: expected_count) do
        perms = Public.user_edit_permissions(create(:user), @repo)
        refute perms.org
        refute perms.repo
      end
    end

    test "returns false if user-owned repo provided" do
      user = create :user
      user_repo = create :repository, owner: user
      assert_authzd_calls(single: 0, batch: 0) do
        perms = Public.user_edit_permissions(user, user_repo)
        refute perms.org
        refute perms.repo
      end
    end
  end

  context "destroy_all_definitions" do
    test "should delete all definitions of the given org" do
      events = subscribe "custom_property_definition.destroy"
      second_org = create :organization
      definition = create :custom_property_definition, source: second_org

      assert_equal CustomPropertyDefinition.defined_by(@org).count, 2
      assert_equal CustomPropertyDefinition.defined_by(second_org).count, 1

      Public.destroy_all_definitions(second_org)

      assert_equal CustomPropertyDefinition.defined_by(@org).count, 2
      assert_equal CustomPropertyDefinition.defined_by(second_org).count, 0

      refute_nil event = events.pop, "an event was expected"
      expected_payload = {
        definition_id: definition.id,
        property_name: definition.property_name,
        description: nil,
        value_type: "string",
        org: second_org.name,
        org_id: second_org.id,
        required: false,
        default_value: nil,
        allowed_values: nil,
      }
      assert_equal expected_payload, event.payload
    end

    test "keeps enterprise definitions when destroying for org" do
      assert_equal CustomPropertyDefinition.defined_by(@org).count, 2
      assert_equal CustomPropertyDefinition.defined_by(@business).count, 1

      Public.destroy_all_definitions(@org)

      assert_equal CustomPropertyDefinition.defined_by(@org).count, 0
      assert_equal CustomPropertyDefinition.defined_by(@business).count, 1
    end

    test "destroys enterprise definitions" do
      assert_equal CustomPropertyDefinition.defined_by(@org).count, 2
      assert_equal CustomPropertyDefinition.defined_by(@business).count, 1

      Public.destroy_all_definitions(@business)

      assert_equal CustomPropertyDefinition.defined_by(@org).count, 2
      assert_equal CustomPropertyDefinition.defined_by(@business).count, 0
    end
  end

  context "destroy_all_properties" do
    test "throws if invalid entity type" do
      exception = assert_raises TypeError do
        Public.destroy_all_properties(create(:user))
      end
      assert exception.message.start_with?("Parameter 'entity': Expected type Repository, got type User")
    end

    test "deletes all properties" do
      custom_property_events = subscribe("custom_property.destroy")
      custom_property_value_events = subscribe("custom_property_value.destroy")
      create :custom_property_value, target: @repo, definition: @definition_env, value: "value"

      assert_equal repo_properties(@repo, :manual), { "environment" => "value" }

      repo_to_keep = create :repository, owner: @org
      create :custom_property_value, target: repo_to_keep, definition: @definition_env, value: "value"

      Public.destroy_all_properties(@repo)
      assert_empty CustomPropertyValue.for_target(@repo)
      assert_equal repo_properties(repo_to_keep, :manual), { "environment" => "value" }

      refute_nil custom_property_value_event = custom_property_value_events.pop, "an event was expected"
      expected_custom_property_value_event = {
        definition_id: @definition_env.id,
        property_name: @definition_env.property_name,
        value: "value",
        repo: @repo.name_with_display_owner,
        repo_id: @repo.id,
        org: @org.display_login,
        org_id: @org.id,
        public_repo: TestEnv.test_with_all_emus? ? false : true,
      }

      assert_equal expected_custom_property_value_event, custom_property_value_event.payload
    end

    test "does not check if owner is org" do
      user = create :user
      repo = create :repository, owner: user

      Public.destroy_all_properties(@repo)
      assert_empty CustomPropertyValue.for_target(@repo)
    end
  end

  context "destroy_property_values" do
    test "deletes all properties for org" do
      create :custom_property_value, target: @repo, definition: @definition_env, value: "staging"
      create :custom_property_value, target: @repo, definition: @biz_definition_version, value: "2.0.0"

      assert_equal repo_properties(@repo, :manual), { "environment" => "staging", "biz_version" => "2.0.0" }

      Public.destroy_property_values(@repo, @org)

      assert_equal repo_properties(@repo, :manual), { "biz_version" => "2.0.0" }
    end

    test "deletes all properties for biz" do
      create :custom_property_value, target: @repo, definition: @definition_env, value: "staging"
      create :custom_property_value, target: @repo, definition: @biz_definition_version, value: "2.0.0"

      assert_equal repo_properties(@repo, :manual), { "environment" => "staging", "biz_version" => "2.0.0" }

      Public.destroy_property_values(@repo, @business)

      assert_equal repo_properties(@repo, :manual), { "environment" => "staging" }
    end
  end

  context "property_usage" do
    test "gets 0 if no usages" do
      definition = create :custom_property_definition, source: @org, property_name: "unused"

      usage = Public.property_usage(definition)
      assert_equal 0, usage[:repositories_count]
    end

    test "gets the number of repos using a property" do
      create :custom_property_value, definition: @definition_env, target: @repo, value: "prod"

      usage = Public.property_usage(@definition_env)
      assert_equal 1, usage[:repositories_count]
    end

    test "gets 0 if used on a deleted repo" do
      repo = create :repository, :soft_deleted, owner: @org
      create :custom_property_value, definition: @definition_env, target: repo, value: "prod"

      assert_query_count(1) do
        usage = Public.property_usage(@definition_env)
        assert_equal 0, usage[:repositories_count]
      end
    end

    test "returns correct count for business property" do
      create :custom_property_value, definition: @biz_definition_version, target: @repo, value: "1.0.0"

      usage = Public.property_usage(@biz_definition_version)
      assert_equal 1, usage[:repositories_count]
    end
  end

  context "shared definitions cache" do
    test "shares definitions cache between managers" do
      definitions_manager = Public.definitions_manager(@org)
      values_manager = Public.values_manager(definitions_manager)

      assert_query_count_per_table({ custom_property_definitions: 1 }) do
        definitions_manager.get_definitions
        values_manager.set_properties_for([@repo], { "environment" => "value" }, actor: @org.admin)
      end
    end

    test "invalidates cache" do
      definitions_manager = Public.definitions_manager(@org)
      values_manager = Public.values_manager(definitions_manager)

      assert_query_count_per_table({
        custom_property_definitions: 3 # 2 select + 1 insert
      }) do
        definitions_manager.save_definition(property_name: "version")
        values_manager.set_properties_for([@repo], { "version" => "1.0.0" }, actor: @org.admin)
      end
    end
  end
end
