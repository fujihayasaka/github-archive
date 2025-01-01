# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationTermsOfServiceUpgradePromptTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user)
    @org = create(:organization, admin: @org_admin)
  end

  context "validations" do
    test "requires an organization" do
      missing_organization = Organization::TermsOfServiceUpgradePrompt.new(upgraded_terms_type: :corporate)
      refute_predicate missing_organization, :valid?
      assert_equal ["Organization can't be blank"], missing_organization.errors.full_messages
    end

    test "requires a upgraded_term_type" do
      missing_upgraded_term_type = Organization::TermsOfServiceUpgradePrompt.new(organization: @org)
      refute_predicate missing_upgraded_term_type, :valid?
      assert_equal ["Upgraded terms type can't be blank"], missing_upgraded_term_type.errors.full_messages
    end

    test "requires org and terms to be unique together" do
      valid_tos_prompt = Organization::TermsOfServiceUpgradePrompt.create(organization: @org, upgraded_terms_type: :corporate)
      assert_predicate valid_tos_prompt, :valid?

      assert_raises ActiveRecord::RecordNotUnique do
        Organization::TermsOfServiceUpgradePrompt.create(organization: @org, upgraded_terms_type: :corporate)
      end
    end
  end
end
