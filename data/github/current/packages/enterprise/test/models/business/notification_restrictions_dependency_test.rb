# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class NotificationRestrictionsDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user)
    @other_org = create(:organization, admin: @user)
    @business = create(:business, owners: [@user], organizations: [@org, @other_org])
    @business_verified_domain = "sombra.example.com"
    @business_approved_domain = "sindra.example.com"
    @org_verified_domain = "arbmos.example.com"
    @domain = create(:verifiable_domain, domain: @business_verified_domain, owner: @business, verified: true)
    @approved_domain = create(:verifiable_domain, domain: @business_approved_domain, owner: @business, approved: true)
    @org_domain = create(:verifiable_domain, domain: @org_verified_domain, owner: @other_org, verified: true)
    @member = create(:user)
    @other_member = create(:user)
    @another_member = create(:user)

    @org.add_member(@member)
    @org.add_member(@other_member)
    @other_org.add_member(@another_member)
  end

  context "#members_without_eligible_email" do
    if GitHub.email_verification_enabled?
      test "with email verification enabled returns members who do not have a verified email that matches a verified or approved domain" do
        @user.add_email("alice@#{@business_verified_domain}").verify!
        @user.add_email("alice@#{@business_approved_domain}")
        @member.add_email("bob@#{@business_verified_domain}")
        @member.add_email("bob@#{@business_approved_domain}")
        @another_member.add_email("charles@#{@org_verified_domain}")
        @another_member.add_email("charles@example.com").verify!

        assert_same_elements [@member, @other_member, @another_member],
          @business.members_without_eligible_email

        @other_member.add_email("rob+verified@#{@org_verified_domain}").verify!
        @another_member.add_email("charles+approved@#{@business_approved_domain}").verify!
        # members_without_eligible_email memoizes the results, so find the Business again
        # (@business.reload isn't enough, sadly)
        business_reloaded = Business.find_by(id: @business.id)
        assert_same_elements [@member, @other_member],
          T.must(business_reloaded).members_without_eligible_email
      end
    else
      test "with email verification disabled returns members who do not have any email that matches a verified or approved domain" do
        @user.add_email("alice@#{@business_verified_domain}")
        @user.add_email("alice@#{@business_approved_domain}")
        @member.add_email("bob@#{@business_verified_domain}")
        @member.add_email("bob@#{@business_approved_domain}")
        @another_member.add_email("charles@#{@org_verified_domain}")
        @another_member.add_email("charles@example.com")

        assert_equal [@other_member],
                     @business.members_without_eligible_email
      end
    end

    test "does not return any users when there are no verified or approved domains in the business" do
      @domain.destroy
      @org_domain.destroy
      @approved_domain.destroy
      @user.add_email("alice@#{@business_verified_domain}").verify!
      @member.add_email("bob@#{@business_verified_domain}")
      @other_member.add_email("rob@#{@business_approved_domain}")

      assert_equal 0, @business.verifiable_domains.verified.count
      assert_empty @business.members_without_eligible_email
    end
  end

  context "#orgs_for_member_without_eligible_email" do
    if GitHub.email_verification_enabled?
      test "with email verification enabled, returns the user's orgs where they don't have a verified email matching the org's verified or approved domains" do
        @user.add_email("alice@#{@business_verified_domain}").verify!
        @member.add_email("bob@#{@business_verified_domain}")
        @another_member.add_email("charles@#{@org_verified_domain}")
        @another_member.add_email("charles@example.com").verify!
        org_admin = create(:user)
        org3 = create(:organization, admin: org_admin)
        @business.add_organization(org3)
        org_admin.add_email("admin@#{@business_verified_domain}").verify!
        other_org_admin = create(:user)
        org4 = create(:organization, admin: other_org_admin)
        @business.add_organization(org4)
        other_org_admin.add_email("rob@#{@business_approved_domain}").verify!

        assert_equal [@org], @business.orgs_for_member_without_eligible_email(@member)
        assert_equal [@org], @business.orgs_for_member_without_eligible_email(@other_member)
        assert_equal [@other_org], @business.orgs_for_member_without_eligible_email(@another_member)
        assert_empty @business.orgs_for_member_without_eligible_email(org_admin)
        assert_empty @business.orgs_for_member_without_eligible_email(other_org_admin)
        assert_empty @business.orgs_for_member_without_eligible_email(@user)
      end
    else
      test "with email verification disabled, returns the user's orgs where they don't have any email matching the org's verified or approved domains" do
        @user.add_email("alice@#{@business_verified_domain}")
        @member.add_email("bob@#{@business_verified_domain}")
        @another_member.add_email("charles@#{@org_verified_domain}")
        @another_member.add_email("charles@example.com")
        org_admin = create(:user)
        org3 = create(:organization, admin: org_admin)
        @business.add_organization(org3)
        org_admin.add_email("admin@#{@business_verified_domain}")
        other_org_admin = create(:user)
        org4 = create(:organization, admin: other_org_admin)
        @business.add_organization(org4)
        other_org_admin.add_email("rob@#{@business_approved_domain}")

        assert_empty @business.orgs_for_member_without_eligible_email(@member)
        assert_equal [@org], @business.orgs_for_member_without_eligible_email(@other_member)
        assert_empty @business.orgs_for_member_without_eligible_email(@another_member)
        assert_empty @business.orgs_for_member_without_eligible_email(org_admin)
        assert_empty @business.orgs_for_member_without_eligible_email(other_org_admin)
        assert_empty @business.orgs_for_member_without_eligible_email(@user)
      end
    end
  end
end
