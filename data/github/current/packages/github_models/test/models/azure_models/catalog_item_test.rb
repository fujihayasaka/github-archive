# typed: true
# frozen_string_literal: true

require "test_helper"

class AzureModels::CatalogItemTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @staff_user = create(:staff_admin_user)
    @static_gpt4 = GitHubModels::Types::Static::GPT4
    @gpt4_catalog_item = AzureModels::CatalogItem.create!(key: "#{@static_gpt4[:registry]}/#{@static_gpt4[:name]}", value: {})
  end

  context "visibility_map" do
    test "returns the correct mapping for visible models" do
      map = AzureModels::CatalogItem.visibility_map(@user)

      assert map["#{@static_gpt4[:registry]}/#{@static_gpt4[:name]}"]
    end

    test "returns the correct mapping for hidden models" do
      @gpt4_catalog_item.hidden!
      map = AzureModels::CatalogItem.visibility_map(@user)

      refute map["#{@static_gpt4[:registry]}/#{@static_gpt4[:name]}"]
    end

    test "returns the correct mapping for staffshipped models and staff users", skip_in_multitenant_mode: true do
      @gpt4_catalog_item.staffshipped!
      map = AzureModels::CatalogItem.visibility_map(@staff_user)

      assert map["#{@static_gpt4[:registry]}/#{@static_gpt4[:name]}"]
    end

    test "returns the correct mapping for staffshipped models and normal users" do
      @gpt4_catalog_item.staffshipped!
      map = AzureModels::CatalogItem.visibility_map(@user)

      refute map["#{@static_gpt4[:registry]}/#{@static_gpt4[:name]}"]
    end

    test "returns the correct mapping for staffshipped models and nil users" do
      @gpt4_catalog_item.staffshipped!
      map = AzureModels::CatalogItem.visibility_map(nil)

      refute map["#{@static_gpt4[:registry]}/#{@static_gpt4[:name]}"]
    end
  end

  context "can_view?" do
    test "true for a visible model" do
      assert AzureModels::CatalogItem.can_view?(user: @user, registry: @static_gpt4[:registry], name: @static_gpt4[:name])
    end

    test "false for a hidden model" do
      @gpt4_catalog_item.hidden!
      refute AzureModels::CatalogItem.can_view?(user: @user, registry: @static_gpt4[:registry], name: @static_gpt4[:name])
    end

    test "true for a staffshipped model and staff user", skip_in_multitenant_mode: true do
      @gpt4_catalog_item.staffshipped!
      assert AzureModels::CatalogItem.can_view?(user: @staff_user, registry: @static_gpt4[:registry], name: @static_gpt4[:name])
    end

    test "false for a staffshipped model and normal user" do
      @gpt4_catalog_item.staffshipped!
      refute AzureModels::CatalogItem.can_view?(user: @user, registry: @static_gpt4[:registry], name: @static_gpt4[:name])
    end

    test "false for a staffshipped model and nil user" do
      @gpt4_catalog_item.staffshipped!
      refute AzureModels::CatalogItem.can_view?(user: nil, registry: @static_gpt4[:registry], name: @static_gpt4[:name])
    end

    test "false for a bad registry/name pair" do
      refute AzureModels::CatalogItem.can_view?(user: nil, registry: "nonsense", name: @static_gpt4[:name])
    end
  end
end unless GitHub.enterprise?
