# typed: false
# frozen_string_literal: true

require "test_helper"

module BusinessExternalProviderMembersSharedTests
  extend ActiveSupport::Concern

  included do
    context "#unlinked_external_identities" do
      test "returns empty if no provider" do
        @business.external_provider.destroy

        assert_empty @business.unlinked_external_identities
      end

      test "returns empty if no external identities" do
        @business.external_provider.external_identities.destroy_all

        assert_empty @business.unlinked_external_identities
      end

      test "returns unlinked external identities" do
        unlinked_external_identities = @business.unlinked_external_identities
        assert_same_elements [@unlinked_external_identity], unlinked_external_identities
        refute_includes unlinked_external_identities, @external_identity
      end
    end

    context "#unlinked_external_identities_count" do
      test "returns 0 if no provider" do
        @business.external_provider.destroy

        assert_equal 0, @business.unlinked_external_identities_count
      end

      test "returns 0 if no external identities" do
        @business.external_provider.external_identities.destroy_all

        assert_equal 0, @business.unlinked_external_identities_count
      end

      test "returns correct count of unlinked external identities" do
        assert_equal 1, @business.unlinked_external_identities_count
      end
    end
  end
end

class BusinessExternalProviderMembersTest < GitHub::TestCase
  include BusinessExternalProviderMembersSharedTests

  fixtures do
    @user = create :user
    @business = create :business
    create :business_saml_provider, business: @business

    @external_identity = create(:external_identity, user: @user, provider: @business.external_provider)

    @user2 = create :user
    @unlinked_external_identity = create(:external_identity, user: @user2, provider: @business.external_provider)
    @unlinked_external_identity.update!(user_id: nil)
  end
end unless GitHub.single_business_environment?

class EmuSAMLBusinessExternalProviderMembersTest < GitHub::TestCase
  include BusinessExternalProviderMembersSharedTests

  fixtures do
    @user = create :emu
    @business = @user.enterprise_managed_business

    @external_identity = @user.external_identities.first

    @user2 = create :emu, business: @business
    @unlinked_external_identity = @user2.external_identities.first
    @unlinked_external_identity.update!(user_id: nil)
  end
end unless GitHub.single_business_environment?

class EmuOIDCBusinessExternalProviderMembersTest < GitHub::TestCase
  include BusinessExternalProviderMembersSharedTests

  fixtures do
    @user = create :emu, provider_type: :oidc
    @business = @user.enterprise_managed_business

    @external_identity = @user.external_identities.first

    @user2 = create :emu, business: @business
    @unlinked_external_identity = @user2.external_identities.first
    @unlinked_external_identity.update!(user_id: nil)
  end
end unless GitHub.single_business_environment?

class GhesWithSCIMBusinessExternalProviderMembersTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  include BusinessExternalProviderMembersSharedTests

  fixtures do
    @user = create :ghes_scim_user
    @business = @user.external_identities.first.provider.business

    @external_identity = @user.external_identities.first

    @user2 = create :ghes_scim_user
    @unlinked_external_identity = @user2.external_identities.first
    @unlinked_external_identity.update!(user_id: nil)
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end
end if GitHub.single_business_environment?
