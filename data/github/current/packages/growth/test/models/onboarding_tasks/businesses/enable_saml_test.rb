# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Businesses
    class BusinessesEnableSamlTest < GitHub::TestCase
      skip_enterprise

      fixtures do
        @owner = create(:user)
        @business = create(:business, owners: [@owner])
        @emu_owner = create(:emu, :owner)
        @emu_business = @emu_owner.enterprise_managed_business
      end

      context "#verify_task" do
        test "returns false if saml is not enabled" do
          Business.any_instance.stubs(:saml_provider).returns(nil)

          refute EnableSaml.new(taskable: @business, user: @owner).verify_task
        end

        test "returns true if saml is enabled" do
          Business.any_instance.stubs(:saml_provider).returns(::Business::SamlProvider.new)

          assert EnableSaml.new(taskable: @business, user: @owner).verify_task
        end
      end

      context "#task_link" do
        context "for non-EMU enterprises" do
          test "returns correct link" do
            assert_equal \
              "/enterprises/#{@business.slug}/settings/security",
              EnableSaml.new(taskable: @business, user: @owner).task_link
          end
        end

        context "for EMU enterprises" do
          [[nil, true], [::Business::SamlProvider.new, false]].each do |provider, emu_onboarding|
            test "returns correct link, provider: #{provider}, emu_onboarding: #{emu_onboarding}" do
              @emu_business.stubs(:saml_provider).returns(provider)

              assert_equal \
                "/enterprises/#{@emu_business.slug}/settings/single_sign_on_configuration?emu_onboarding=#{emu_onboarding}",
                EnableSaml.new(taskable: @emu_business, user: @emu_owner).task_link
            end
          end
        end
      end

      context "#help_link" do
        context "for non-EMU enterprises" do
          test "returns correct link" do
            assert_match \
              %r[admin/managing-iam/understanding-iam-for-enterprises/about-saml-for-enterprise-iam],
              EnableSaml.new(taskable: @business, user: @owner).help_link
          end
        end

        context "for EMU enterprises" do
          test "returns correct link" do
            assert_match \
              %r[admin/managing-iam/configuring-authentication-for-enterprise-managed-users],
              EnableSaml.new(taskable: @emu_business, user: @emu_owner).help_link
          end
        end
      end
    end
  end
end
