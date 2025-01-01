# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Businesses
    class BusinessesEnableSamlTest < GitHub::TestCase
      fixtures do
        @owner = create(:user)
        @business = create(:business, owners: [@owner])
      end

      context  "verify_task" do
        test "returns false if saml is not enabled" do
          Business.any_instance.stubs(:saml_provider).returns(nil)

          assert_equal false, EnableSaml.new(taskable: @business, user: @owner).verify_task
        end

        test "returns true if saml is enabled" do
          Business.any_instance.stubs(:saml_provider).returns(::Business::SamlProvider.new)

          assert_equal true, EnableSaml.new(taskable: @business, user: @owner).verify_task
        end
      end
    end
  end
end
