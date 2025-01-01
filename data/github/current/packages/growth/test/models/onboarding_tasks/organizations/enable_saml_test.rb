# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Organizations
    class OrganizationsEnableSamlTest < GitHub::TestCase
      fixtures do
        @owner = create(:user)
        @business = create(:business, owners: [@owner])
        @org = create(:organization, login: "ACME", admin: @owner, business: @business)
      end

      context  "verify_task" do
        test "returns false if saml is not enabled" do
          create(:repository, owner: @org)

          assert_equal false, EnableSaml.new(taskable: @org, user: @owner).verify_task
        end

        test "returns true if saml is enabled" do
          Organization.any_instance.stubs(:saml_provider).returns(::Organization::SamlProvider.new)

          assert EnableSaml.new(taskable: @org, user: @owner).verify_task
        end

        test "returns true if business saml is enabled" do
          Business.any_instance.stubs(:saml_provider).returns(::Business::SamlProvider.new)

          assert EnableSaml.new(taskable: @org, user: @owner).verify_task
        end
      end
    end
  end
end
