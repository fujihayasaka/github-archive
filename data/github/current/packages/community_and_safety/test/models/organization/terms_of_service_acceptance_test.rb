# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationTermsOfServiceAcceptanceTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user)
    @org = create(:organization, admin: @org_admin)
  end

  context "validations" do
    test "requires an organization" do
      missing_organization = Organization::TermsOfServiceAcceptance.new
      refute_predicate missing_organization, :valid?
      assert_equal ["Organization can't be blank"], missing_organization.errors.full_messages
    end

    test "requires organization to be unique" do
      valid_tos = Organization::TermsOfServiceAcceptance.create(organization: @org)
      assert_predicate valid_tos, :valid?

      assert_raises ActiveRecord::RecordNotUnique do
        Organization::TermsOfServiceAcceptance.create(organization: @org)
      end
    end
  end

  test "defaults to `Standard` terms type" do
    terms = Organization::TermsOfServiceAcceptance.create(organization: @org)

    assert_predicate terms, :standard?
  end
end
