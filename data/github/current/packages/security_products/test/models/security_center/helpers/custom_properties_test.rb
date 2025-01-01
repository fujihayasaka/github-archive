# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Helpers
    class CustomPropertiesTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        @org_1 = create(:organization, admin: @user)
        @org_2 = create(:organization, admin: @user)

        @custom_property_definitions_org_1 = create_list(:custom_property_definition, 10, source: @org_1)
        @custom_property_definitions_org_2 = create_list(:custom_property_definition, 10, source: @org_2)
      end

      context "#definitions_for_frontend" do
        test "it returns the custom property definitions for the given org" do
          assert_same_elements(
            @custom_property_definitions_org_1.map { |definition| { name: definition.property_name, type: definition.value_type } },
            SecurityCenter::Helpers::CustomProperties.new(org: @org_1, user: @user).definitions_for_frontend
          )
        end

        test "it limits the number of items returned" do
          create_list(:custom_property_definition, ::CustomProperties::Public::DEFINITION_LIMIT + 1, source: @org_1)

          assert_equal(
            ::CustomProperties::Public::DEFINITION_LIMIT,
            SecurityCenter::Helpers::CustomProperties.new(org: @org_1, user: @user).definitions_for_frontend.size
          )
        end
      end
    end
  end
end
