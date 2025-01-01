# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomPropertiesDefinitionsManagerUsagesTest < Api::TestCase
  include CustomProperties

  setup do
    @org = create :organization
    @definitions_manager = Public.definitions_manager(@org)

    @definition_env = create :custom_property_definition, source: @org, property_name: "environment"

    @default_usage_values = {
      definition: @definition_env,
      consumer_type: :ruleset,
      property_value: "production"
    }

    @definition_security = create :custom_property_definition, source: @org, property_name: "security"
    @usage_env_production = create :custom_property_usage, **@default_usage_values.merge(property_value: "production")
    @usage_env_development = create :custom_property_usage,
      consumer_id: @usage_env_production.consumer_id,
      **@default_usage_values.merge(property_value: "development")
  end

  test "updates condition usage overwriting existing usages" do
    consumer_id = @usage_env_production.consumer_id

    assert_equal %w[production development], CustomPropertyUsage.where(consumer_id: consumer_id).order(id: :asc).map(&:property_value)

    queries = {
      delete: 2, # Delete existing usages
      select: 2, # Select definitions
      insert: 2, # Insert usages
    }
    assert_query_count(queries.values.sum) do
      @definitions_manager.register_usage(:ruleset, consumer_id, [%w(environment development), %w(security critical)])
    end

    assert_equal %w[development critical], CustomPropertyUsage.where(consumer_id: consumer_id).order(id: :asc).map(&:property_value)
  end

  test "updates condition usage ignores duplicates" do
    usage = create :custom_property_usage, **@default_usage_values.merge(property_value: "production")
    consumer_id = usage.consumer_id

    assert_equal ["production"], CustomPropertyUsage.where(consumer_id: consumer_id).map(&:property_value)
    @definitions_manager.register_usage(:ruleset, consumer_id, [%w(environment development), %w(environment development)])

    assert_equal ["development"], CustomPropertyUsage.where(consumer_id: consumer_id).map(&:property_value)
  end

  test "fails to update if definition does not exist" do
    exception = assert_raises ArgumentError do
      @definitions_manager.register_usage(
        :ruleset,
        @usage_env_production.consumer_id,
        [%w(framework rails)]
      )
    end

    assert_equal exception.message, "Property 'framework' is not defined"
  end

  test "deletes properties usages using consumer ids" do
    CustomPropertyUsage.destroy_all
    assert_equal 0, CustomPropertyUsage.count

    consumer_10 = 10
    consumer_20 = 20

    contoso = create :organization
    definition_env_in_contoso = create :custom_property_definition, property_name: "env", source: contoso
    create :custom_property_usage,
      **@default_usage_values.merge(consumer_id: consumer_10, definition: definition_env_in_contoso)
    create :custom_property_usage,
      **@default_usage_values.merge(consumer_id: consumer_20, definition: definition_env_in_contoso)

    definition_security_in_contoso = create :custom_property_definition, property_name: "security", source: contoso
    create :custom_property_usage,
      **@default_usage_values.merge(consumer_id: consumer_10, definition: definition_security_in_contoso)
    create :custom_property_usage,
      **@default_usage_values.merge(consumer_id: consumer_20, definition: definition_security_in_contoso)

    acme = create :organization
    definition_env_in_acme = create :custom_property_definition, property_name: "env", source: acme
    create :custom_property_usage,
      **@default_usage_values.merge(consumer_id: consumer_10, definition: definition_env_in_acme)
    create :custom_property_usage,
      **@default_usage_values.merge(consumer_id: consumer_20, definition: definition_env_in_acme)

    assert_equal 6, CustomPropertyUsage.count

    Public.definitions_manager(contoso).delete_usages(:ruleset, consumer_10)

    assert_equal 4, CustomPropertyUsage.count

    assert_equal definition_env_in_contoso.usages.sort_by(&:id), get_usages(contoso, "env")
    assert_equal definition_security_in_contoso.usages.sort_by(&:id), get_usages(contoso, "security")
    assert_equal definition_env_in_acme.usages.sort_by(&:id), get_usages(acme, "env")
  end

  test "propagates consumer type validation errors" do
    exception = assert_raises CustomProperties::Errors::InvalidPropertyUsage do
      @definitions_manager.register_usage(:invalid, 1, [%w(environment development)])
    end

    assert_equal exception.message, "Validation failed: Consumer type 'invalid' is unknown consumer type"
  end

  test "retrieves usages by property name" do
    usages = @definitions_manager.get_condition_usages("environment")
    assert_equal usages.sort_by(&:id), [@usage_env_production, @usage_env_development]
  end

  test "retrieves usages by property name and value" do
    usages = @definitions_manager.get_condition_usages("environment", property_value: "production")
    assert_equal usages, [@usage_env_production]
  end

  test "limits returned usages to 50 items" do
    51.times do |i|
      create :custom_property_usage, **@default_usage_values.merge(property_value: "value #{i + 1}")
    end
    usages = @definitions_manager.get_condition_usages("environment")
    assert_equal usages.size, 50
  end

  test "retrieves empty if no matches" do
    assert_empty @definitions_manager.get_condition_usages("security")
  end

  test "retrieves empty if definition does not exist" do
    assert_empty @definitions_manager.get_condition_usages("unknown")
  end

  def get_usages(org, property_name)
    CustomPropertyUsage
      .includes(:definition)
      .where(definition: { source_id: org.id, property_name: property_name })
      .order(id: :asc)
  end
end
