# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Businesses
    class CreateOrganizationTest < GitHub::TestCase
      fixtures do
        @owner = create(:user)
        @admin = create(:user)
        @business = create(:business, owners: [@owner])
        @org = create(:organization, login: "ACME", admin: @owner)
      end

      context "verify_task" do
        test "returns false if no organizations" do
          @business.organizations.destroy_all

          assert_equal false, CreateOrganization.new(taskable: @business, user: @owner).verify_task
        end

        test "returns true if there are organizations" do
          @business.add_organization(@org)

          assert_equal true, CreateOrganization.new(taskable: @business, user: @owner).verify_task
        end
      end

      context "completed?" do
        test "returns falsy value if previous organizations are deleted" do
          @business.add_organization(@org)
          @business.organizations.destroy_all

          refute_equal true, CreateOrganization.new(taskable: @business, user: @owner).completed?
        end

        test "returns true if there is at leaset one organization" do
          @business.add_organization(@org)
          assert_equal true, CreateOrganization.new(taskable: @business, user: @owner).completed?
        end
      end
    end
  end
end
