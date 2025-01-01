# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Businesses
    class GeneratePersonalAccessTokenTest < GitHub::TestCase
      skip_enterprise

      fixtures do
        @owner = create(:emu, :owner)
        @business = @owner.enterprise_managed_business
        @first_admin = @business.find_first_emu_owner
      end

      context "#verify_task" do
        test "returns false if user does not have any oauth tokens" do
          refute_predicate GeneratePersonalAccessToken.new(taskable: @business, user: @first_admin), :verify_task
        end

        test "returns true if user does has any oauth tokens" do
          personal_access = create(:personal_token_oauth_access, user: @first_admin, description: Sham.sha)

          assert_predicate GeneratePersonalAccessToken.new(taskable: @business, user: @first_admin), :verify_task
        end
      end

      context "completed?" do
        test "returns false if user does not have any oauth tokens" do
          refute_predicate GeneratePersonalAccessToken.new(taskable: @business, user: @first_admin), :verify_task
        end

        test "returns true if user does has any oauth tokens" do
          personal_access = create(:personal_token_oauth_access, user: @first_admin, description: Sham.sha)

          assert_predicate GeneratePersonalAccessToken.new(taskable: @business, user: @first_admin), :verify_task
        end
      end
    end
  end
end
