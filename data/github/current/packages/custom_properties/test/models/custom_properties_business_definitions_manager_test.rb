# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomPropertiesBusinessDefinitionsManagerTest < Api::TestCase
  include CustomProperties
  include CustomProperties::Errors
  include CustomPropertiesTestHelper

  setup do
    @biz_org = create :enterprise_linked_organization, name: "acme"
    @biz = @biz_org.business
    GitHub.flipper[:enterprise_custom_properties].enable(@biz)
    @biz_org_repo = create :repository, owner: @biz_org

    @org = create :organization
    create :repository, owner: @org

    @biz_def_manager = Public.business_definitions_manager(@biz)

    GitHub.flipper[:skip_bulk_repos_index_job].disable
  end

  context "initialize" do
    test "raises if initializing manager with unsupported source" do
      exception = assert_raises TypeError do
        Public.business_definitions_manager(@org)
      end

      assert_match "Expected type Business, got type Organization", exception.message
    end

    test "raises if directly initializing manager with unsupported source" do
      exception = assert_raises TypeError do
        CustomPropertiesBusinessDefinitionsManager.new(@org)
      end

      assert_match "Expected type Business, got type Organization", exception.message
    end

    test "raises if enterprise properties flag disabled" do
      @biz.disable_feature(:enterprise_custom_properties)

      exception = assert_raises ArgumentError do
        Public.business_definitions_manager(@biz)
      end

      assert_equal "Unsupported source type: 'Business'", exception.message
    end
  end

  context "promote_definition" do
    test "can promote an org definition to enterprise" do
      definition = create :custom_property_definition, :string, source: @biz_org, property_name: "ENV"
      prop_value = create :custom_property_value, definition: definition, target: @biz_org_repo, value: "test"

      @biz_def_manager.promote_definition(definition)

      result = @biz_def_manager.get_definitions
      assert_equal result.size, 1

      biz_def = result.first
      assert_equal biz_def.property_name, "ENV"
      assert_equal biz_def.id, definition.id
      assert biz_def.business_source_type?

      assert_equal [prop_value], CustomPropertyValue.for_target(@biz_org_repo)
    end

    test "raises if biz property is promoted" do
      definition = create :custom_property_definition, :string, source: @biz, property_name: "ENV"

      exception = assert_raises ArgumentError do
        @biz_def_manager.promote_definition(definition)
      end

      assert_equal exception.message, "Enterprise property cannot be promoted"
    end

    test "raises if already exists in the enterprise schema" do
      create :custom_property_definition, :string, source: @biz, property_name: "ENV"
      definition = create :custom_property_definition, :string, source: @biz_org, property_name: "ENV"

      exception = assert_raises ArgumentError do
        @biz_def_manager.promote_definition(definition)
      end

      assert_equal exception.message, "Property already exists in the enterprise schema"
    end

    test "raises if promoting property hits schema limit" do
      definition = create :custom_property_definition, :string, source: @biz_org, property_name: "ENV"
      definitions = create :custom_property_definition, :string, source: @biz

      Public.stub_const(:DEFINITION_LIMIT, 1) do
        assert_raises DefinitionLimitReachedError do
          @biz_def_manager.promote_definition(definition)
        end
      end
    end

    test "raises if property does not exist" do
      definition = create :custom_property_definition, :string, source: @biz_org, property_name: "ENV"
      definition.destroy!

      exception = assert_raises ArgumentError do
        @biz_def_manager.promote_definition(definition)
      end

      assert_equal exception.message, "Property not found"
    end

    test "raises if another property with the same name exists in another enterprise org" do
      another_org = create :enterprise_linked_organization, business: @biz, name: "another-org"

      definition = create :custom_property_definition, :string, source: @biz_org, property_name: "ENV"
      create :custom_property_definition, :string, source: another_org, property_name: "Env"

      exception = assert_raises ArgumentError do
        @biz_def_manager.promote_definition(definition)
      end

      assert_equal exception.message, "Cannot promote property. Property 'ENV' is already defined in 'another-org'. Property name uniqueness is case insensitive."
    end
  end

  context "child_orgs_definitions_by_name" do
    test "should return for business org, case insensitively" do
      create :custom_property_definition, source: @biz_org, property_name: "environment"
      duplicate_properties = @biz_def_manager.child_orgs_definitions_by_name("ENVIRONMENT")
      assert_equal duplicate_properties.first.property_name, "environment"
    end

    test "should return empty for no match in business org" do
      create :custom_property_definition, source: @biz_org, property_name: "environment"
      duplicate_properties = @biz_def_manager.child_orgs_definitions_by_name("zzzzz")
      assert_empty duplicate_properties
    end
  end
end
