# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Businesses
    class CreateOverviewReadmeTest < GitHub::TestCase
      fixtures do
        @owner = create :user
        @business = create :business, owners: [@owner]
      end

      context "#verify_task" do
        test "returns false if Business has no README" do
          refute_predicate CreateOverviewReadme.new(taskable: @business, user: @owner), :verify_task
        end

        test "returns true if Business has README" do
          @business.update! long_description: "Very good README"

          assert_predicate CreateOverviewReadme.new(taskable: @business, user: @owner), :verify_task
        end
      end

      context "#completed?" do
        test "returns false if README is cleared" do
          @business.update! long_description: "Very good README"
          @business.update! long_description: ""

          refute_predicate CreateOverviewReadme.new(taskable: @business, user: @owner), :completed?
        end

        test "returns true if Business has README" do
          @business.update! long_description: "Very good README"

          assert_predicate CreateOverviewReadme.new(taskable: @business, user: @owner), :completed?
        end
      end
    end
  end
end
