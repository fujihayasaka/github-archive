# typed: true
# frozen_string_literal: true

require "test_helper"

class DeleteConflictCustomPropertyDefinitionsJobTest < GitHub::TestCase
  fixtures do
    @business = create :business
    @org = create :organization

    enable_feature_flag(:enterprise_custom_properties)
  end

  unless GitHub.enterprise?
    test "does nothing if no properties" do
      DeleteConflictCustomPropertyDefinitionsJob.perform_now(org: @org, business: @business)

      assert_equal 0, CustomProperties::Public.definitions_manager(@org).get_definitions.count
    end

    test "deletes organization definition with conflicting name on business" do
      bizprop_one = create :custom_property_definition, source: @business, property_name: "one"
      bizprop_two = create :custom_property_definition, source: @business, property_name: "two"
      orgprop_two = create :custom_property_definition, source: @org, property_name: "TWO"
      orgprop_three = create :custom_property_definition, source: @org, property_name: "three"

      assert_equal 2, CustomProperties::Public.business_definitions_manager(@business).get_definitions.count
      assert_equal 2, CustomProperties::Public.definitions_manager(@org).get_definitions.count

      DeleteConflictCustomPropertyDefinitionsJob.perform_now(org: @org, business: @business)

      assert_equal 2, CustomProperties::Public.business_definitions_manager(@business).get_definitions.count
      assert_equal 1, CustomProperties::Public.definitions_manager(@org).get_definitions.count

      assert_raises(ActiveRecord::RecordNotFound) { orgprop_two.reload }
    end

    test "won't try to delete source business definitions" do
      org = create :enterprise_linked_organization
      source_biz = org.business

      source_bizprop_one = create :custom_property_definition, source: source_biz, property_name: "one"
      target_bizprop_one = create :custom_property_definition, source: @business, property_name: "one"

      DeleteConflictCustomPropertyDefinitionsJob.perform_now(org: org, business: @business)

      assert_equal 1, CustomProperties::Public.business_definitions_manager(source_biz).get_definitions.count
    end
  end
end
