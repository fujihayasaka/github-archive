# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomPropertiesDefinitionsManagerTest < Api::TestCase
  include CustomProperties
  include CustomProperties::Errors
  include CustomPropertiesTestHelper

  fixtures do
    create_search_indices
    setup_search
  end

  setup do
    @biz_org = create :enterprise_linked_organization, name: "acme"
    @biz = @biz_org.business
    GitHub.flipper[:enterprise_custom_properties].enable(@biz)
    @biz_org_repo = create :repository, owner: @biz_org

    @org = create :organization
    create :repository, owner: @org

    @biz_def_manager = Public.business_definitions_manager(@biz)
    @biz_org_def_manager = Public.definitions_manager(@biz_org)

    @org_def_manager = Public.definitions_manager(@org)
    GitHub.flipper[:skip_bulk_repos_index_job].disable
  end

  teardown_once do
    teardown_search
  end

  context "get_definitions" do
    test "should return empty array if no definitions are set" do
      assert_equal @org_def_manager.get_definitions, []
    end

    test "returns org and enterprise definitions for enterprize org and only enterprise definitions for enterprise" do
      create :custom_property_definition, :string, source: @biz_org, property_name: "org_string"
      create :custom_property_definition, :string, source: @biz, property_name: "enterprise_string"

      assert_equal @biz_org_def_manager.get_definitions.pluck(:property_name), %w[enterprise_string org_string]
      assert_equal @biz_def_manager.get_definitions.pluck(:property_name), %w[enterprise_string]
    end

    test "works for an org without enterprise" do
      create :custom_property_definition, :string, source: @org, property_name: "org_string"

      assert_equal @org_def_manager.get_definitions.pluck(:property_name), %w[org_string]
    end

    test "handles duplicate property names in favor of bizprops" do
      org_def = create :custom_property_definition, :string, source: @biz_org, property_name: "dupe"
      biz_def = create :custom_property_definition, :string, source: @biz, property_name: "DUPE"

      assert_equal @biz_org_def_manager.get_definitions, [biz_def]
      assert_equal @biz_def_manager.get_definitions, [biz_def]
    end

    test "returns definitions defined for the source without resolving the schema" do
      org_def = create :custom_property_definition, :string, source: @biz_org, property_name: "dupe"
      biz_def = create :custom_property_definition, :string, source: @biz, property_name: "DUPE"

      assert_equal @biz_org_def_manager.get_definitions(only_defined_by_source: true), [org_def]
      assert_equal @biz_def_manager.get_definitions(only_defined_by_source: true), [biz_def]
    end
  end

  context "get_definition" do
    test "should return definition by name case-insensitive" do
      org_def = create :custom_property_definition, :string, source: @biz_org, property_name: "dupe"
      biz_def = create :custom_property_definition, :string, source: @biz, property_name: "DUPE"

      assert_equal @biz_org_def_manager.get_definition("dupe"), biz_def
      assert_equal @biz_def_manager.get_definition("dupe"), biz_def
    end
  end

  context "own_definitions_count" do
    test "should return the count of definitions owned by the source" do
      create :custom_property_definition, :string, source: @biz_org, property_name: "org_string"
      create :custom_property_definition, :string, source: @biz, property_name: "enterprise_string"

      assert_equal @biz_org_def_manager.own_definitions_count, 1
      assert_equal @biz_def_manager.own_definitions_count, 1
    end
  end

  context "save_definition" do
    [:no_biz_org, :biz_org, :biz].each do |type|
      test "#{type}: should save definition" do
        manager, source_type = manager_and_source(type)

        definition_d = manager.save_definition(property_name: "property_name_d", value_type: "multi_select", allowed_values: %w[ios web])
        definition_c = manager.save_definition(property_name: "property_name_c")
        definition_b = manager.save_definition(property_name: "property_name_b")
        definition_a = manager.save_definition(
          property_name: "property_name_a",
          value_type: "single_select",
          required: true,
          default_value: "prod",
          description: "Short description",
          allowed_values: %w[prod test],
          values_editable_by: "org_and_repo_actors",
        )

        assert_equal manager.get_definitions, [definition_a, definition_b, definition_c, definition_d]
      end

      test "#{type}: replaces definition with the same property name" do
        manager, source_type = manager_and_source(type)
        definition = manager.save_definition(property_name: "version")

        assert_equal definition.values_editable_by, "org_actors"

        definition = manager.save_definition(
          property_name: "version",
          value_type: "string",
          description: "Current version",
          values_editable_by: "org_and_repo_actors",
        )

        assert_equal definition.property_name, "version"
        assert_equal definition.value_type, "string"
        assert_equal definition.description, "Current version"
        assert_nil definition.allowed_values
        assert_equal definition.values_editable_by, "org_and_repo_actors"
        assert_equal manager.get_definitions, [definition]
      end
    end

    test "creates definitions with same name for orgs in one enterprise" do
      another_org = create :enterprise_linked_organization, business: @biz
      another_org_def_manager = Public.definitions_manager(another_org)

      biz_org_def = @biz_org_def_manager.save_definition(property_name: "version")
      biz_another_org_def = another_org_def_manager.save_definition(property_name: "version")

      assert_equal @biz_org_def_manager.get_definitions, [biz_org_def]
      assert_equal another_org_def_manager.get_definitions, [biz_another_org_def]
    end

    test "should ensure uniqueness of allowed_values" do
      exception = assert_raises ActiveRecord::RecordInvalid do
        CustomPropertyDefinition.create!(
          property_name: "language",
          allowed_values: %w[ruby python java ruby],
          value_type: "single_select"
        )
      end

      assert_equal exception.message, "Validation failed: Allowed values contains duplicates: ruby"
    end

    test "allows deleting unused allowed values with different casing" do
      repo = create :repository, owner: @org
      definition = CustomPropertyDefinition.new property_name: "language", value_type: "single_select", source: @org, allowed_values: %w[ruby RUBY]
      definition.save validate: false

      create :custom_property_value, definition: definition, target: repo, value: "ruby"

      definition = @org_def_manager.save_definition(
        property_name: "language",
        value_type: "single_select",
        allowed_values: %w[ruby]
      )

      assert_equal definition.allowed_values, %w[ruby]
    end

    test "allows biz manager to update a property with duplicate name" do
      create :custom_property_definition, :string, source: @biz_org, property_name: "dupe"
      biz_def = create :custom_property_definition, :string, source: @biz, property_name: "DUPE"

      result = @biz_def_manager.save_definition(property_name: "dupe", description: "updated")

      assert_equal result.id, biz_def.id
      assert biz_def.reload.description, "updated"
    end

    test "raises if org manager tries to update a property with duplicate name" do
      create :custom_property_definition, :string, source: @biz_org, property_name: "dupe"
      create :custom_property_definition, :string, source: @biz, property_name: "DUPE"

      exception = assert_raises InvalidDefinition do
        @biz_org_def_manager.save_definition(property_name: "dupe")
      end

      assert_equal exception.message, "Cannot change 'DUPE'. Property is defined at enterprise level."
    end

    test "raises if org manager tries to create a property with duplicate name" do
      create :custom_property_definition, :string, source: @biz, property_name: "DUPE"

      exception = assert_raises InvalidDefinition do
        @biz_org_def_manager.save_definition(property_name: "dupe")
      end

      assert_equal exception.message, "Cannot change 'DUPE'. Property is defined at enterprise level."
    end

    test "raises if too many definitions" do
      100.times do |i|
        @org_def_manager.save_definition(property_name: "property_name_#{i}")
      end

      assert_raises DefinitionLimitReachedError do
        @org_def_manager.save_definition(property_name: "environment")
      end
    end

    test "raises if invalid property name" do
      exception = assert_raises InvalidDefinition do
        @org_def_manager.save_definition(property_name: "no:colons")
      end
      assert_equal exception.message, "Validation failed: Property name is invalid"
    end

    %w[string single_select].each do |value_type|
      test "raises if no default_value for a required #{value_type} definition" do
        exception = assert_raises InvalidDefinition do
          @org_def_manager.save_definition(
            property_name: "env",
            value_type: value_type,
            required: true,
            allowed_values: (%w[prod test] if value_type == "single_select")
          )
        end
        assert_equal exception.message, "Validation failed: Default value must be present"
      end

      test "raises if default_value for a no required #{value_type} definition" do
        exception = assert_raises InvalidDefinition do
          @org_def_manager.save_definition(
            property_name: "env",
            value_type: value_type,
            default_value: "prod",
            allowed_values: (%w[prod test] if value_type == "single_select")
          )
        end
        assert_equal exception.message, "Validation failed: Default value must be empty"
      end
    end

    test "raises if default_value is not part of the allowed_values" do
      exception = assert_raises InvalidDefinition do
        @org_def_manager.save_definition(
          property_name: "env",
          required: true,
          value_type: "single_select",
          default_value: "staging",
          allowed_values: %w[prod test]
        )
      end
      assert_equal exception.message, "Validation failed: Default value must be part of the allowed values"
    end

    test "raises if description is too long" do
      exception = assert_raises InvalidDefinition do
        @org_def_manager.save_definition(property_name: "env", description: "a" * 256)
      end
      assert_equal exception.message, "Validation failed: Description must be at most 255 characters"
    end

    test "raises if allowed values are invalid" do
      exception = assert_raises InvalidDefinition do
        @org_def_manager.save_definition(property_name: "env", value_type: "single_select", allowed_values: ["no\"quotes"])
      end

      assert_equal exception.message, "Validation failed: Allowed values 'no\"quotes' contains invalid characters: \""
    end

    test "raises if allowed values are not unique after stripping and downcasing" do
      exception = assert_raises InvalidDefinition do
        @org_def_manager.save_definition(property_name: "env", value_type: "single_select", allowed_values: ["prod", "Prod", "prod unique"])
      end

      assert_equal exception.message, "Validation failed: Allowed values contains duplicates: prod"
    end

    test "raises if allowed values provided with a string type" do
      exception = assert_raises InvalidDefinition do
        @org_def_manager.save_definition(property_name: "env", allowed_values: ["123"])
      end

      assert_equal exception.message, "Validation failed: Allowed values must be nil if value_type is string"
    end

    test "raises if single_select with no allowed values" do
      exception = assert_raises InvalidDefinition do
        @org_def_manager.save_definition(property_name: "env", value_type: "single_select")
      end

      assert_equal exception.message, "Validation failed: Allowed values must be present if value_type is single_select"
    end

    test "raises with empty value type" do
      exception = assert_raises InvalidDefinition do
        @org_def_manager.save_definition(property_name: "env", value_type: "")
      end

      assert_equal exception.message, "Validation failed: Value type can't be blank"
    end

    test "raises with invalid value type" do
      exception = assert_raises ArgumentError do
        @org_def_manager.save_definition(property_name: "env", value_type: "foobar")
      end

      assert_equal exception.message, "'foobar' is not a valid value_type"
    end

    test "raises if values_editable_by invalid" do
      exception = assert_raises ArgumentError do
        @org_def_manager.save_definition(property_name: "env", value_type: "string", values_editable_by: "invalid")
      end

      assert_equal exception.message, "'invalid' is not a valid values_editable_by"
    end

    test "raises if value_type is changed" do
      definition = @org_def_manager.save_definition(property_name: "environment")

      exception = assert_raises InvalidDefinition do
        @org_def_manager.save_definition(
          property_name: "environment",
          value_type: "single_select",
          description: "Either test or prod",
          allowed_values: ["prod"],
          values_editable_by: "org_and_repo_actors",
        )
      end

      assert_equal "Unable to save 'environment'. Value type cannot be changed.", exception.message
    end

    test "raises if removing an allowed value in use" do
      repo = create :repository, owner: @org
      definition = create :custom_property_definition, :single_select, source: @org, property_name: "language", allowed_values: %w[ruby python]
      create :custom_property_value, definition: definition, target: repo, value: "ruby"

      exception = assert_raises DefinitionDeletionAllowValueInUseError do
        @org_def_manager.save_definition(
          property_name: "language",
          value_type: "single_select",
          allowed_values: %w[python java golang]
        )
      end

      assert_equal "Unable to save 'language' because you can't delete options that are in use: 'ruby' referenced by 1 active repository.", exception.message
    end

    test "raises if removing multiple allowed values in use" do
      repo = create :repository, owner: @org
      second_repo = create :repository, owner: @org
      third_repo = create :repository, owner: @org
      definition = create :custom_property_definition, :single_select, source: @org, property_name: "language", allowed_values: %w[ruby python golang]
      create :custom_property_value, definition: definition, target: repo, value: "ruby"
      create :custom_property_value, definition: definition, target: second_repo, value: "python"
      create :custom_property_value, definition: definition, target: third_repo, value: "python"

      exception = assert_raises DefinitionDeletionAllowValueInUseError do
        @org_def_manager.save_definition(
          property_name: "language",
          value_type: "single_select",
          allowed_values: %w[java golang typescript]
        )
      end

      assert_equal "Unable to save 'language' because you can't delete options that are in use: 'python', 'ruby' referenced by 3 active repositories.", exception.message
    end

    test "raises if initializing manager with unsupported source" do
      exception = assert_raises TypeError do
        Public.definitions_manager(@biz)
      end

      assert_match "Expected type Organization, got type Business", exception.message
    end

    test "raises if directly initializing manager with unsupported source" do
      exception = assert_raises ArgumentError do
        CustomPropertiesDefinitionsManager.new(@biz)
      end

      assert_match "Avoid using 'CustomPropertiesDefinitionsManager' unless working with 'Organization' source", exception.message
    end

    test "can remove an allowed value that's only used in soft-deleted repos" do
      repo = create :repository, :soft_deleted, owner: @org
      definition = create :custom_property_definition, :single_select, source: @org, property_name: "language", allowed_values: %w[ruby python]
      saved_value = create :custom_property_value, definition: definition, target: repo, value: "ruby"

      @org_def_manager.save_definition(
        property_name: "language",
        value_type: "single_select",
        allowed_values: %w[python java]
      )

      assert_raises ActiveRecord::RecordNotFound do
        saved_value.reload
      end
    end

    test "should run 2 queries, one select and one update, when creating a definition" do
      queries = {
        insert: 1,
        select: 1,
      }
      assert_query_count_per_table({ custom_property_definitions: queries[:insert] + queries[:select] }) do
        @org_def_manager.save_definition(property_name: "environment", description: "This is a description")
      end
    end

    test "should run 2 queries, one select and one update, when updating a definition" do
      queries = {
        update: 1,
        select: 1,
      }
      @org_def_manager.save_definition(property_name: "environment")
      assert_query_count_per_table({ custom_property_definitions: queries[:update] + queries[:select] }) do
        @org_def_manager.save_definition(property_name: "environment", description: "This is a description")
      end
    end

    test "should have a single SQL query, select, if no update" do
      queries = {
        select: 1,
      }

      @org_def_manager.save_definition(
        property_name: "environment",
        description: "This is a description",
        value_type: "single_select",
        allowed_values: %w[prod test],
        required: true,
        default_value: "prod",
      )

      assert_query_count_per_table({ custom_property_definitions: queries[:select] }) do
        @org_def_manager.save_definition(
          property_name: "environment",
          description: "This is a description",
          value_type: "single_select",
          allowed_values: %w[prod test],
          required: true,
          default_value: "prod",
        )
      end
    end

    test "raises if org source tries to updated biz property" do
      create :custom_property_definition, source: @biz, property_name: "biz_string"
      exception = assert_raises InvalidDefinition do
        @biz_org_def_manager.save_definition(property_name: "biz_string", description: "This is a description")
      end

      assert_equal exception.message, "Cannot change 'biz_string'. Property is defined at enterprise level."
    end

    test "org source: saving definition with same case-insensitive name results in update" do
      @org_def_manager.save_definition(property_name: "Environment")
      definition = @org_def_manager.save_definition(property_name: "ENVironment", description: "update")

      assert_equal @org_def_manager.get_definitions, [definition]
      assert_equal definition.property_name, "Environment"
      assert_equal definition.description, "update"
    end

    test "business source: saving definition with same case-insensitive name results in update" do
      create :custom_property_definition, source: @biz, property_name: "Environment"
      definition = @biz_def_manager.save_definition(property_name: "ENVironment", description: "update")

      assert_equal @biz_def_manager.get_definitions, [definition]
      assert_equal definition.property_name, "Environment"
      assert_equal definition.description, "update"
    end

    test "raises if org definition exists in business schema" do
      create :custom_property_definition, source: @biz, property_name: "Environment"
      exception = assert_raises InvalidDefinition do
        @biz_org_def_manager.save_definition(property_name: "ENVironment")
      end

      assert_equal exception.message, "Cannot change 'Environment'. Property is defined at enterprise level."

      definitions = @biz_org_def_manager.get_definitions
      assert_equal definitions.count, 1
    end

    test "raises if business definition exists in one of the orgs schemas" do
      create :custom_property_definition, source: @biz_org, property_name: "Environment"
      exception = assert_raises ArgumentError do
        @biz_def_manager.save_definition(property_name: "ENVironment")
      end

      assert_equal exception.message, "Failed to save custom property. Property 'ENVironment' is already defined in 'acme'. Property name uniqueness is case insensitive."

      definitions = @biz_def_manager.get_definitions
      assert_equal definitions.count, 0
    end
  end

  context "delete_definition" do
    test "should delete definition by key" do
      definition = @org_def_manager.save_definition(property_name: "property_name_a")
      assert_equal @org_def_manager.get_definitions.size, 1

      assert_equal @org_def_manager.delete_definition("property_name_a"), definition
      assert_equal @org_def_manager.get_definitions, []
    end

    test "returns nil if entry does not exist" do
      assert_nil @org_def_manager.delete_definition("non_existent_prop_name")
    end

    test "raises if definition has usages" do
      definition = @org_def_manager.save_definition(property_name: "property_name_a")
      create :custom_property_usage, definition: definition

      exception = assert_raises DefinitionDeletionError do
        @org_def_manager.delete_definition("property_name_a")
      end

      assert_equal exception.message, "Property definition '#{definition.property_name}' has usages and cannot be deleted"
    end

    test "should remove the custom_properties_values when removing a definition" do
      repo_a = create :repository, owner: @org
      repo_b = create :repository, owner: @org
      definition = create :custom_property_definition, source: @org, property_name: "environment"
      create :custom_property_value, definition: definition, target: repo_a, value: "test"
      create :custom_property_value, definition: definition, target: repo_b, value: "prod"

      assert_equal @org_def_manager.get_definitions.size, 1
      assert_equal repo_properties(repo_a, :manual), { "environment" => "test" }
      assert_equal repo_properties(repo_b, :manual), { "environment" => "prod" }

      @org_def_manager.delete_definition("environment")

      assert_equal @org_def_manager.get_definitions, []
      assert_empty repo_properties(repo_a, :manual)
      assert_empty repo_properties(repo_b, :manual)
    end

    test "should run 2 queries, one select and one delete, when deleting an existing definition" do
      @org_def_manager.save_definition(property_name: "environment")
      queries = {
        delete: 1,
        select: 1,
      }
      assert_query_count_per_table({ custom_property_definitions: queries[:select] + queries[:delete] }) do
        @org_def_manager.delete_definition("environment")
      end
    end

    test "should run 1 query and no delete when trying to delete an non-existing definition" do
      @org_def_manager.save_definition(property_name: "environment")
      queries = {
        select: 1,
      }
      assert_query_count_per_table({ custom_property_definitions: queries[:select] }) do
        @org_def_manager.delete_definition("invalidPropertyName")
      end
    end

    test "should run queries in custom_property_values when deleting an existing definition" do
      definition = @org_def_manager.save_definition(property_name: "environment")

      repo_a = create :repository, owner: @org
      create :custom_property_value, definition:, target: repo_a, value: "test"
      repo_b = create :repository, owner: @org
      create :custom_property_value, definition:, target: repo_b, value: "prod"

      assert_equal 2, definition.values.count
      assert_equal definition.values.map(&:target_id), [repo_a.id, repo_b.id]

      assert_query_count_per_table({
        custom_property_definitions: 2, # 1 select + 1 delete
        custom_property_values: 1,
        custom_properties: 0
        }) do
          @org_def_manager.delete_definition("environment")
        end

      new_org_def_manager = Public.definitions_manager(@org)
      assert_empty new_org_def_manager.get_definitions
      assert_empty CustomPropertyValue.for_target(repo_a)
      assert_empty CustomPropertyValue.for_target(repo_b)
    end

    test "does nothing if org source tries to delete biz property" do
      create :custom_property_definition, source: @biz, property_name: "biz_string"
      assert_nil @biz_org_def_manager.delete_definition("biz_string")
    end
  end

  context "reindex all org repos" do
    test "should not if a non-required definition is added" do
      assert_enqueued_jobs 0, only: BulkReposIndexJob do
        @org_def_manager.save_definition(property_name: "new_property")
      end
    end

    test "should when a required definition is added" do
      assert_enqueued_jobs 1, only: BulkReposIndexJob do
        @org_def_manager.save_definition(property_name: "new_property", required: true, default_value: "default")
      end
    end

    test "should not when a required definition fails to be added" do
      assert_enqueued_jobs 0, only: BulkReposIndexJob do
        assert_raises InvalidDefinition do
          @org_def_manager.save_definition(property_name: "new property", required: true, default_value: "default")
        end
      end
    end

    test "should when an existing definition becomes required" do
      definition = create :custom_property_definition, source: @org, property_name: "environment"

      assert_enqueued_jobs 1, only: BulkReposIndexJob do
        @org_def_manager.save_definition(property_name: "environment", required: true, default_value: "default")
      end
    end

    test "should when an existing required definition becomes non-required" do
      definition = create :custom_property_definition, source: @org, property_name: "environment", required: true, default_value: "default"

      assert_enqueued_jobs 1, only: BulkReposIndexJob do
        @org_def_manager.save_definition(property_name: "environment", required: false, default_value: "")
      end
    end

    test "should when an existing required definition changes its default value" do
      definition = create :custom_property_definition, source: @org, property_name: "environment", required: true, default_value: "default"

      assert_enqueued_jobs 1, only: BulkReposIndexJob do
        @org_def_manager.save_definition(property_name: "environment", required: true, default_value: "new_default")
      end
    end

    test "should not when a non-required definition changes" do
      definition = create :custom_property_definition, source: @org, property_name: "environment", value_type: "single_select", allowed_values: %w[staging dev]

      assert_enqueued_jobs 0, only: BulkReposIndexJob do
        @org_def_manager.save_definition(property_name: "environment", value_type: "single_select", allowed_values: %w[prod test])
      end
    end

    test "should when a definition is deleted" do
      create :custom_property_definition, source: @org, property_name: "environment"

      assert_enqueued_jobs 1, only: BulkReposIndexJob do
        @org_def_manager.delete_definition("environment")
      end
    end
  end

  context "merge_definitions" do
    test "should merge definitions based on property name case-insensitive and return sorted array" do
      org_def_security = create :custom_property_definition, source: @org, property_name: "security"
      org_def_env = create :custom_property_definition, source: @org, property_name: "environment"
      biz_def_cost_center = create :custom_property_definition, source: @org, property_name: "const_center"
      biz_def_env = create :custom_property_definition, source: @biz, property_name: "ENVIRONMENT"

      org_defs = [org_def_security, org_def_env]
      biz_defs = [biz_def_cost_center, biz_def_env]

      result = CustomPropertiesDefinitionsManager.merge_definitions(biz_defs, org_defs)

      assert_equal result, [biz_def_cost_center, biz_def_env, org_def_security]
    end

  end

  def manager_and_source(type)
    options = {
      no_biz_org: [@org_def_manager, "org"],
      biz_org: [@biz_org_def_manager, "org"],
      biz: [@biz_def_manager, "business"],
    }

    raise "Invalid type: #{type}" unless options.key?(type)

    options[type]
  end
end
