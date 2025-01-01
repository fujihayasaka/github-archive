# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module UnifiedAlerts
    module Groups
      class ByCustomPropertyTest < GitHub::TestCase
        extend T::Sig

        fixtures do
          @biz = create(:business)
          @org_admin = create(:user)
          @org = create(:organization, business: @biz, admin: @org_admin)
          @repo = create(:private_repository, owner: @org)

          @custom_property_boolean = create(:custom_property_definition, :true_false, source: @org)
          @custom_property_single = create(:custom_property_definition, :single_select, source: @org)
          @custom_property_multi = create(:custom_property_definition, :multi_select, source: @org)
          @custom_property_string = create(:custom_property_definition, :string, source: @org)
        end

        context "#finalize" do
          test "includes property name for boolean properties" do
            items = [
              { name: "true" },
              { name: "false" },
            ]
            result = ByCustomProperty.new(scope: @org, user: @org_admin, group_key: "repo.props.#{@custom_property_boolean.property_name}").finalize(items)

            assert_equal 2, result.count
            assert_equal "#{@custom_property_boolean.property_name}: true", result.dig(0, :name)
            assert_equal "#{@custom_property_boolean.property_name}: false", result.dig(1, :name)
          end

          test "does not include property name for single-select properties" do
            items = [
              { name: "aaa" },
              { name: "bbb" },
            ]
            result = ByCustomProperty.new(scope: @org, user: @org_admin, group_key: "props.#{@custom_property_single.property_name}").finalize(items)

            assert_equal 2, result.count
            assert_equal "aaa", result.dig(0, :name)
            assert_equal "bbb", result.dig(1, :name)
          end

          test "does not include property name for multi-select properties" do
            items = [
              { name: "aaa" },
              { name: "bbb" },
            ]
            result = ByCustomProperty.new(scope: @org, user: @org_admin, group_key: "props.#{@custom_property_multi.property_name}").finalize(items)

            assert_equal 2, result.count
            assert_equal "aaa", result.dig(0, :name)
            assert_equal "bbb", result.dig(1, :name)
          end

          test "does not include property name for string properties" do
            items = [
              { name: "aaa" },
              { name: "bbb" },
            ]
            result = ByCustomProperty.new(scope: @org, user: @org_admin, group_key: "props.#{@custom_property_string.property_name}").finalize(items)

            assert_equal 2, result.count
            assert_equal "aaa", result.dig(0, :name)
            assert_equal "bbb", result.dig(1, :name)
          end
        end
      end
    end
  end
end
