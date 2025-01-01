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

      context "task_link" do
        [[nil, true], [::Business::SamlProvider.new, false]].each do |provider, emu_onboarding|
          test "returns correct link when ff enabled, provider: #{provider}, emu_onboarding: #{emu_onboarding}" do
            GitHub.flipper[:move_emu_sso_configuration_page].enable(@business)
            Business.any_instance.stubs(:saml_provider).returns(provider)

            link = EnableSaml.new(taskable: @business, user: @owner).task_link
            assert_equal "/enterprises/#{@business.slug}/settings/single_sign_on_configuration?emu_onboarding=#{emu_onboarding}", link
          end
        end
      end
    end
  end
end
