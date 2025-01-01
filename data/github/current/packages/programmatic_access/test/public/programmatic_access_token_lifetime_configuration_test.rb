# typed: true
# frozen_string_literal: true

require "test_helper"

class ProgrammaticAccessTokenLifetimeConfigurationTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers

  fixtures do
    @user = create :user
  end

  context "business_organizations_exceeding_limit" do
    test "returns organizations exceeding the expiration limit for a business" do
      business = create :business
      org1 = create :organization, business: business
      org2 = create :organization, business: business
      org3 = create :organization, business: business
      org4 = create :organization, business: business # no limit set

      org1.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 25)
      org2.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 30)
      org3.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 35)

      business.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 30)

      organizations = ProgrammaticAccessTokenLifetimeConfiguration.business_organizations_exceeding_limit(business, ProgrammaticAccessTokenType::FineGrained, business.fine_grained_personal_access_token_expiration_limit)

      assert_equal [org3], organizations
    end
  end

  context "fine-grained personal access tokens" do
    context "#set_maximum_lifetime_configuration" do
      test "sets expiration limit for businesses" do
        business = create :business
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::FineGrained)
        configuration.set_maximum_lifetime_configuration(@user, 30)

        assert_equal 30, business.fine_grained_personal_access_token_expiration_limit
      end

      test "sets expiration limit for organizations" do
        organization = create :organization
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::FineGrained)
        configuration.set_maximum_lifetime_configuration(@user, 30)

        assert_equal 30, organization.fine_grained_personal_access_token_expiration_limit
      end
    end

    context "#expiration_limit" do
      test "returns expiration limit for businesses" do
        business = create :business
        business.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 30)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::FineGrained)

        assert_equal 30, configuration.expiration_limit
      end

      test "returns expiration limit for organizations" do
        organization = create :organization
        organization.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 30)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::FineGrained)

        assert_equal 30, configuration.expiration_limit
      end
    end

    context ".expiration_limit_for" do
      test "returns expiration limit for businesses" do
        business = create :business
        business.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 30)

        assert_equal 30, ProgrammaticAccessTokenLifetimeConfiguration.expiration_limit_for(business, ProgrammaticAccessTokenType::FineGrained)
      end

      test "returns expiration limit for organizations" do
        organization = create :organization
        organization.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 30)

        assert_equal 30, ProgrammaticAccessTokenLifetimeConfiguration.expiration_limit_for(organization, ProgrammaticAccessTokenType::FineGrained)
      end
    end

    context "#personal_access_token_expiration_limit_enabled?" do
      test "returns true for businesses with an expiration limit" do
        business = create :business
        business.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 30)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::FineGrained)

        assert configuration.personal_access_token_expiration_limit_enabled?
      end

      test "returns true for organizations with an expiration limit" do
        organization = create :organization
        organization.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 30)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::FineGrained)

        assert configuration.personal_access_token_expiration_limit_enabled?
      end

      test "returns false for businesses without an expiration limit" do
        business = create :business
        business.disable_fine_grained_personal_access_token_expiration_limit(actor: @user)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::FineGrained)

        refute configuration.personal_access_token_expiration_limit_enabled?
      end

      test "returns false for organizations without an expiration limit" do
        organization = create :organization
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::FineGrained)

        refute configuration.personal_access_token_expiration_limit_enabled?
      end
    end

    context "#disable_personal_access_token_expiration_limit" do
      test "disables expiration limit for businesses with limits" do
        business = create :business
        business.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 30)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::FineGrained)
        configuration.disable_personal_access_token_expiration_limit(@user)

        refute business.fine_grained_personal_access_token_expiration_limit
      end

      test "disables expiration limit for organizations" do
        organization = create :organization
        organization.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 30)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::FineGrained)
        configuration.disable_personal_access_token_expiration_limit(@user)

        refute organization.fine_grained_personal_access_token_expiration_limit
      end
    end

    context "#enable_exemptions" do
      test "enables exemptions for businesses" do
        business = create :business
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::FineGrained)
        configuration.enable_exemptions(@user)

        assert business.fine_grained_personal_access_token_expiration_limit_exemption_enabled?
      end

      test "does not enable exemptions for organizations or their businesses" do
        organization = create :organization, business: create(:business)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::FineGrained)
        configuration.enable_exemptions(@user)

        refute organization.business.fine_grained_personal_access_token_expiration_limit_exemption_enabled?
      end
    end

    context "#disable_exemptions" do
      test "disables exemptions for businesses" do
        business = create :business
        business.enable_fine_grained_personal_access_token_expiration_limit_exemption(actor: @user)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::FineGrained)
        configuration.disable_exemptions(@user)

        refute business.fine_grained_personal_access_token_expiration_limit_exemption_enabled?
      end

      test "does not disable exemptions for organizations or their businesses" do
        organization = create :organization, business: create(:business)
        organization.business.enable_fine_grained_personal_access_token_expiration_limit_exemption(actor: @user)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::FineGrained)
        configuration.disable_exemptions(@user)

        assert organization.business.fine_grained_personal_access_token_expiration_limit_exemption_enabled?
      end
    end

    context "#exemptions_enabled?" do
      test "returns true for businesses with exemptions enabled" do
        business = create :business
        business.enable_fine_grained_personal_access_token_expiration_limit_exemption(actor: @user)

        assert ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::FineGrained).exemptions_enabled?
      end

      test "returns false for businesses without exemptions enabled" do
        business = create :business

        refute ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::FineGrained).exemptions_enabled?
      end

      test "returns false for organizations with no business exemption enabled" do
        organization = create :organization

        refute ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::FineGrained).exemptions_enabled?
      end

      test "returns false for organizations with a business exemption enabled" do
        organization = create :organization, business: create(:business)
        organization.business.enable_fine_grained_personal_access_token_expiration_limit_exemption(actor: @user)

        refute ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::FineGrained).exemptions_enabled?
      end
    end

    context ".exemptions_enabled_for?" do
      test "returns true for businesses with exemptions enabled" do
        business = create :business
        business.enable_fine_grained_personal_access_token_expiration_limit_exemption(actor: @user)

        assert ProgrammaticAccessTokenLifetimeConfiguration.exemptions_enabled_for?(business, ProgrammaticAccessTokenType::FineGrained)
      end

      test "returns false for businesses without exemptions enabled" do
        business = create :business

        refute ProgrammaticAccessTokenLifetimeConfiguration.exemptions_enabled_for?(business, ProgrammaticAccessTokenType::FineGrained)
      end

      test "returns false for organizations with no business exemption enabled" do
        organization = create :organization

        refute ProgrammaticAccessTokenLifetimeConfiguration.exemptions_enabled_for?(organization, ProgrammaticAccessTokenType::FineGrained)
      end

      test "returns false for organizations with a business exemption enabled" do
        organization = create :organization, business: create(:business)
        organization.business.enable_fine_grained_personal_access_token_expiration_limit_exemption(actor: @user)

        refute ProgrammaticAccessTokenLifetimeConfiguration.exemptions_enabled_for?(organization, ProgrammaticAccessTokenType::FineGrained)
      end
    end
  end

  context "classic personal access tokens" do
    context "#set_maximum_lifetime_configuration" do
      test "sets expiration limit for businesses" do
        business = create :business
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::Classic)
        configuration.set_maximum_lifetime_configuration(@user, 30)

        assert_equal 30, business.personal_access_token_classic_expiration_limit
      end

      test "sets expiration limit for organizations" do
        organization = create :organization
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::Classic)
        configuration.set_maximum_lifetime_configuration(@user, 30)

        assert_equal 30, organization.personal_access_token_classic_expiration_limit
      end
    end

    context "#expiration_limit" do
      test "returns expiration limit for businesses" do
        business = create :business
        business.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 30)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::Classic)

        assert_equal 30, configuration.expiration_limit
      end

      test "returns expiration limit for organizations" do
        organization = create :organization
        organization.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 30)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::Classic)

        assert_equal 30, configuration.expiration_limit
      end
    end

    context ".expiration_limit_for" do
      test "returns expiration limit for businesses" do
        business = create :business
        business.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 30)

        assert_equal 30, ProgrammaticAccessTokenLifetimeConfiguration.expiration_limit_for(business, ProgrammaticAccessTokenType::Classic)
      end

      test "returns expiration limit for organizations" do
        organization = create :organization
        organization.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 30)

        assert_equal 30, ProgrammaticAccessTokenLifetimeConfiguration.expiration_limit_for(organization, ProgrammaticAccessTokenType::Classic)
      end
    end

    context "#personal_access_token_expiration_limit_enabled?" do
      test "returns true for businesses with an expiration limit" do
        business = create :business
        business.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 30)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::Classic)

        assert configuration.personal_access_token_expiration_limit_enabled?
      end

      test "returns true for organizations with an expiration limit" do
        organization = create :organization
        organization.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 30)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::Classic)

        assert configuration.personal_access_token_expiration_limit_enabled?
      end

      test "returns false for businesses without an expiration limit" do
        business = create :business
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::Classic)

        refute configuration.personal_access_token_expiration_limit_enabled?
      end

      test "returns false for organizations without an expiration limit" do
        organization = create :organization
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::Classic)

        refute configuration.personal_access_token_expiration_limit_enabled?
      end
    end

    context "#disable_personal_access_token_expiration_limit" do
      test "disables expiration limit for businesses with limits" do
        business = create :business
        business.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 30)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::Classic)
        configuration.disable_personal_access_token_expiration_limit(@user)

        refute business.personal_access_token_classic_expiration_limit
      end

      test "disables expiration limit for organizations" do
        organization = create :organization
        organization.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 30)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::Classic)
        configuration.disable_personal_access_token_expiration_limit(@user)

        refute organization.personal_access_token_classic_expiration_limit
      end
    end

    context "#enable_exemptions" do
      test "enables exemptions for businesses" do
        business = create :business
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::Classic)
        configuration.enable_exemptions(@user)

        assert business.personal_access_token_classic_expiration_limit_exemption_enabled?
      end

      test "does not enable exemptions for organizations or their businesses" do
        organization = create :organization, business: create(:business)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::Classic)
        configuration.enable_exemptions(@user)

        refute organization.business.personal_access_token_classic_expiration_limit_exemption_enabled?
      end
    end

    context "#disable_exemptions" do
      test "disables exemptions for businesses" do
        business = create :business
        business.enable_personal_access_token_classic_expiration_limit_exemption(actor: @user)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::Classic)
        configuration.disable_exemptions(@user)

        refute business.personal_access_token_classic_expiration_limit_exemption_enabled?
      end

      test "does not disable exemptions for organizations or their businesses" do
        organization = create :organization, business: create(:business)
        organization.business.enable_personal_access_token_classic_expiration_limit_exemption(actor: @user)
        configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::Classic)
        configuration.disable_exemptions(@user)

        assert organization.business.personal_access_token_classic_expiration_limit_exemption_enabled?
      end
    end

    context "#exemptions_enabled?" do
      test "returns true for businesses with exemptions enabled" do
        business = create :business
        business.enable_personal_access_token_classic_expiration_limit_exemption(actor: @user)

        assert ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::Classic).exemptions_enabled?
      end

      test "returns false for businesses without exemptions enabled" do
        business = create :business

        refute ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::Classic).exemptions_enabled?
      end

      test "returns false for organizations with no business exemption enabled" do
        organization = create :organization

        refute ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::Classic).exemptions_enabled?
      end

      test "returns refute for organizations with a business exemption enabled" do
        organization = create :organization, business: create(:business)
        organization.business.enable_personal_access_token_classic_expiration_limit_exemption(actor: @user)

        refute ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::Classic).exemptions_enabled?
      end
    end

    if GitHub.enterprise?
      context "#enable_issued_at_exemption" do
        test "enables exemptions for businesses" do
          business = create :business
          configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::Classic)
          configuration.enable_issued_at_exemption(@user)

          assert business.personal_access_token_classic_missing_issued_at_exemption_enabled?
        end
      end

      context "#disable_issued_at_exemption" do
        test "disables exemptions for businesses" do
          business = create :business
          business.enable_personal_access_token_classic_missing_issued_at_exemption(actor: @user)
          configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::Classic)
          configuration.disable_issued_at_exemption(@user)

          refute business.personal_access_token_classic_missing_issued_at_exemption_enabled?
        end
      end

      context "#issued_at_exemption_enabled?" do
        test "returns true for businesses with exemptions enabled" do
          business = create :business
          business.enable_personal_access_token_classic_missing_issued_at_exemption(actor: @user)

          assert ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::Classic).issued_at_exemption_enabled?
        end

        test "returns false for businesses without exemptions enabled" do
          business = create :business

          refute ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::Classic).issued_at_exemption_enabled?
        end

        test "returns true for organizations where the business has the exemption enabled" do
          organization = create :organization, business: create(:business)
          organization.business.enable_personal_access_token_classic_missing_issued_at_exemption(actor: @user)

          assert ProgrammaticAccessTokenLifetimeConfiguration.new(organization, ProgrammaticAccessTokenType::Classic).issued_at_exemption_enabled?
        end
      end
    end


    context ".exemptions_enabled_for?" do
      test "returns true for businesses with exemptions enabled" do
        business = create :business
        business.enable_personal_access_token_classic_expiration_limit_exemption(actor: @user)

        assert ProgrammaticAccessTokenLifetimeConfiguration.exemptions_enabled_for?(business, ProgrammaticAccessTokenType::Classic)
      end

      test "returns false for businesses without exemptions enabled" do
        business = create :business

        refute ProgrammaticAccessTokenLifetimeConfiguration.exemptions_enabled_for?(business, ProgrammaticAccessTokenType::Classic)
      end

      test "returns false for organizations with no business exemption enabled" do
        organization = create :organization

        refute ProgrammaticAccessTokenLifetimeConfiguration.exemptions_enabled_for?(organization, ProgrammaticAccessTokenType::Classic)
      end

      test "returns refute for organizations with a business exemption enabled" do
        organization = create :organization, business: create(:business)
        organization.business.enable_personal_access_token_classic_expiration_limit_exemption(actor: @user)

        refute ProgrammaticAccessTokenLifetimeConfiguration.exemptions_enabled_for?(organization, ProgrammaticAccessTokenType::Classic)
      end
    end
  end
end
