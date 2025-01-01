# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Businesses
    class AddAzureSubscriptionTest < GitHub::TestCase
      skip_enterprise

      fixtures do
        @owner = create :user
        @business = create :business, owners: [@owner]
      end

      context "#verify_task" do
        test "returns false if Business has no Azure subscription" do
          refute_predicate AddAzureSubscription.new(taskable: @business, user: @owner), :verify_task
        end

        test "returns true if Business has Azure subscription" do
          with = create :business, :with_azure_subscription, owners: [@owner]

          assert_predicate AddAzureSubscription.new(taskable: with, user: @owner), :verify_task
        end
      end

      context "#completed?" do
        test "returns false if Business has no Azure subscription" do
          refute_predicate AddAzureSubscription.new(taskable: @business, user: @owner), :completed?
        end

        test "returns true if Business has Azure subscription" do
          with = create :business, :with_azure_subscription, owners: [@owner]

          assert_predicate AddAzureSubscription.new(taskable: with, user: @owner), :completed?
        end
      end
    end
  end
end
