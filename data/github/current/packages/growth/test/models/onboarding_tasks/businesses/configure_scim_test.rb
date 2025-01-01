# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Businesses
    class ConfigureSCIMTest < GitHub::TestCase
      skip_enterprise

      fixtures do
        @business = create :business, business_type: :enterprise_managed, shortcode: "scim"
        @first_admin = @business.find_first_emu_owner
      end

      context "#verify_task" do
        test "returns false if business only has first admin account" do
          refute_predicate ConfigureSCIM.new(taskable: @business, user: @first_admin), :verify_task
        end

        test "returns true if business has any other users" do
          create :emu, business: @business

          assert_predicate ConfigureSCIM.new(taskable: @business, user: @first_admin), :verify_task
        end
      end

      context "completed?" do
        test "returns false if business only has first admin account" do
          refute_predicate ConfigureSCIM.new(taskable: @business, user: @first_admin), :completed?
        end

        test "returns true business has any other users" do
          create :emu, business: @business

          assert_predicate ConfigureSCIM.new(taskable: @business, user: @first_admin), :completed?
        end
      end
    end
  end
end
