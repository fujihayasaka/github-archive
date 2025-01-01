# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessVerifiableDomainsTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers
  include GitHub::ZuoraTestHelper
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers
  include TurboghasHelpers

  fixtures do
    @owner = create :user
    @user = create :user, login: "user"
    @member1 = create(:user, :verified, login: "member1")
    @org1 = create :organization, plan: GitHub::Plan.business_plus, seats: 10
    @org1.add_member(@member1)
    @org2 = create :organization, plan: GitHub::Plan.business_plus, seats: 10

    only = [SyncBusinessOrganizationBillingSettingsJob, BusinessOrganizationBillingJob]
    @business = perform_enqueued_jobs only: only do
      create :business, name: "CDE Ltd", owners: [@owner], organizations: [@org1, @org2], seats: 20
    end
  end

  context "#email_eligible_domains" do
    test "only returns verified and approved domains for the business" do
      rando_domain = create(:verifiable_domain, verified: true)
      business_domain = create(:verifiable_domain, owner: @business, verified: true)
      approved_rando_domain = create(:verifiable_domain, approved: true)
      approved_business_domain = create(:verifiable_domain, owner: @business, approved: true)
      unverified_business_domain = create(:verifiable_domain, owner: @business)

      assert_same_elements [business_domain, approved_business_domain], @business.email_eligible_domains
    end
  end

  context "#update_dependent_notification_restriction_policies!" do
    test "enables policy for orgs w/verified domains if it was enabled for business" do
      domain = create(:verifiable_domain, owner: @business, verified: true)
      create(:verifiable_domain, owner: @business)
      create(:verifiable_domain, owner: @org1, verified: true)
      create(:verifiable_domain, owner: @org2)

      refute @org1.restrict_notifications_to_verified_domains?
      refute @org2.restrict_notifications_to_verified_domains?

      @business.update_dependent_notification_restriction_policies!(domain.id, actor: @owner, notifications_restricted: true)

      assert @org1.reload.restrict_notifications_to_verified_domains?
      refute @org2.reload.restrict_notifications_to_verified_domains?
    end

    test "enables policy for orgs w/approved domains if it was enabled for business" do
      domain = create(:verifiable_domain, owner: @business, approved: true)
      create(:verifiable_domain, owner: @business)
      create(:verifiable_domain, owner: @org1, approved: true)
      create(:verifiable_domain, owner: @org2)

      refute @org1.restrict_notifications_to_verified_domains?
      refute @org2.restrict_notifications_to_verified_domains?

      @business.update_dependent_notification_restriction_policies!(domain.id, actor: @owner, notifications_restricted: true)

      assert @org1.reload.restrict_notifications_to_verified_domains?
      refute @org2.reload.restrict_notifications_to_verified_domains?
    end

    test "does not notify members when enabling policy for an org" do
      domain = create(:verifiable_domain, owner: @business, verified: true)
      create(:verifiable_domain, owner: @business)
      create(:verifiable_domain, owner: @org1, verified: true)

      refute @org1.restrict_notifications_to_verified_domains?

      assert_no_difference "ActionMailer::Base.deliveries.count" do
        only = [ApplicationDeliveryJob, NotifyNotificationRestrictedMembersJob]
        perform_enqueued_jobs(only: only) do
          @business.update_dependent_notification_restriction_policies!(domain.id, actor: @owner, notifications_restricted: true)
        end
      end
    end

    test "disables policy for orgs w/out verified or approved domains if it was not enabled for business" do
      domain = create(:verifiable_domain, owner: @business, verified: true)
      create(:verifiable_domain, owner: @business)
      create(:verifiable_domain, owner: @org1, verified: true)
      create(:verifiable_domain, owner: @org2)

      refute @business.restrict_notifications_to_verified_domains?
      @org1.enable_notification_restrictions(actor: @owner)
      @org2.enable_notification_restrictions(actor: @owner)

      @business.update_dependent_notification_restriction_policies!(domain.id, actor: @owner, notifications_restricted: false)

      assert @org1.reload.restrict_notifications_to_verified_domains?
      refute @org2.reload.restrict_notifications_to_verified_domains?
    end

    test "does nothing if enterprise has other verified and approved domains and policy was enabled" do
      domain = create(:verifiable_domain, owner: @business, verified: true)
      create(:verifiable_domain, owner: @business, verified: true)
      create(:verifiable_domain, owner: @business, approved: true)
      create(:verifiable_domain, owner: @org1, verified: true)
      create(:verifiable_domain, owner: @org1, approved: true)

      refute @org1.restrict_notifications_to_verified_domains?

      @business.update_dependent_notification_restriction_policies!(domain.id, actor: @owner, notifications_restricted: true)

      refute @org1.reload.restrict_notifications_to_verified_domains?
    end

    test "does nothing if enterprise has other verified and approved domains and policy was not enabled" do
      domain = create(:verifiable_domain, owner: @business, verified: true)
      create(:verifiable_domain, owner: @business, verified: true)
      create(:verifiable_domain, owner: @business, approved: true)
      create(:verifiable_domain, owner: @org1)

      @org1.reload.enable_notification_restrictions(actor: @owner)
      assert @org1.reload.restrict_notifications_to_verified_domains?

      @business.update_dependent_notification_restriction_policies!(domain.id, actor: @owner, notifications_restricted: false)

      assert @org1.reload.restrict_notifications_to_verified_domains?
    end
  end

  context "#email_eligible_domain_user_emails_for" do
    context "fix memoization bug" do
      test "does not return emails from previous checked user" do
        domain1 = create(:verifiable_domain, owner: @business, verified: true)
        domain2 = create(:verifiable_domain, owner: @business, approved: true)
        emails = ["email@#{domain1.domain}", "address@#{domain2.domain}", "nope@not-#{domain1.domain}.com"]
        emails.each { |email| @member1.add_email(email).verify! }

        eligible_emails = emails[0..1]
        results = @business.email_eligible_domain_user_emails_for(@org1, @member1).map(&:email)
        assert_same_elements eligible_emails, results

        nomails_member = create(:user, :verified, login: "nomails")
        @org1.add_member(nomails_member)
        results = @business.email_eligible_domain_user_emails_for(@org1, nomails_member).map(&:email)
        refute_same_elements eligible_emails, results
      end

      test "returns emails even if the previous checked useer didn't have any" do
        domain1 = create(:verifiable_domain, owner: @business, verified: true)
        domain2 = create(:verifiable_domain, owner: @business, approved: true)
        emails = ["email@#{domain1.domain}", "address@#{domain2.domain}", "nope@not-#{domain1.domain}.com"]
        emails.each { |email| @member1.add_email(email).verify! }

        eligible_emails = emails[0..1]

        nomails_member = create(:user, :verified, login: "nomails")
        @org1.add_member(nomails_member)
        results = @business.email_eligible_domain_user_emails_for(@org1, nomails_member).map(&:email)
        refute_same_elements eligible_emails, results

        results = @business.email_eligible_domain_user_emails_for(@org1, @member1).map(&:email)
        assert_same_elements eligible_emails, results
      end
    end

    test "returns verified and approved domains owned by the business for the user that match" do
      domain1 = create(:verifiable_domain, owner: @business, verified: true)
      domain2 = create(:verifiable_domain, owner: @business, approved: true)
      emails = ["email@#{domain1.domain}", "address@#{domain2.domain}", "nope@not-#{domain1.domain}.com"]
      emails.each { |email| @member1.add_email(email).verify! }

      eligible_emails = emails[0..1]
      results = @business.email_eligible_domain_user_emails_for(@org1, @member1).map(&:email)
      assert_same_elements eligible_emails, results
    end

    test "returns verified and approved domains owned by the business and the org for the user that match" do
      domain1 = create(:verifiable_domain, owner: @business, verified: true)
      domain2 = create(:verifiable_domain, owner: @org1, verified: true)
      domain3 = create(:verifiable_domain, owner: @business, approved: true)
      domain4 = create(:verifiable_domain, owner: @org1, approved: true)
      emails = [
        "email@#{domain1.domain}",
        "address@#{domain2.domain}",
        "email@#{domain3.domain}",
        "address@#{domain4.domain}",
        "nope@not-#{domain1.domain}.com"
      ]
      emails.each { |email| @member1.add_email(email).verify! }

      eligible_emails = emails[0..3]
      results = @business.email_eligible_domain_user_emails_for(@org1, @member1).map(&:email)
      assert_same_elements eligible_emails, results
    end

    test "can just get the verified domain emails" do
      domain1 = create(:verifiable_domain, owner: @business, verified: true)
      domain2 = create(:verifiable_domain, owner: @org1, verified: true)
      domain3 = create(:verifiable_domain, owner: @business, approved: true)
      domain4 = create(:verifiable_domain, owner: @org1, approved: true)
      emails = [
        "verified@#{domain1.domain}",
        "verified@#{domain2.domain}",
        "approved@#{domain3.domain}",
        "approved@#{domain4.domain}",
        "nope@not-#{domain1.domain}.com"
      ]
      emails.each { |email| @member1.add_email(email).verify! }

      verified_emails = emails[0..1]
      results = @business.email_eligible_domain_user_emails_for(
        @org1, @member1, include_approved: false
      ).map(&:email)
      assert_same_elements verified_emails, results
    end

    test "can just get the approved domain emails" do
      domain1 = create(:verifiable_domain, owner: @business, verified: true)
      domain2 = create(:verifiable_domain, owner: @org1, verified: true)
      domain3 = create(:verifiable_domain, owner: @business, approved: true)
      domain4 = create(:verifiable_domain, owner: @org1, approved: true)
      emails = [
          "verified@#{domain1.domain}",
          "verified@#{domain2.domain}",
          "approved@#{domain3.domain}",
          "approved@#{domain4.domain}",
          "nope@not-#{domain1.domain}.com"
      ]
      emails.each { |email| @member1.add_email(email).verify! }

      approved_emails = emails[2..3]
      results = @business.email_eligible_domain_user_emails_for(
          @org1, @member1, include_verified: false
      ).map(&:email)
      assert_same_elements approved_emails, results
    end

    if GitHub.email_verification_enabled?
      test "with email verification enabled, only returns verified emails" do
        domain = create(:verifiable_domain, owner: @business, verified: true)
        emails = ["email@#{domain.domain}", "address@#{domain.domain}"]
        @member1.add_email(emails[0]).verify!
        @member1.add_email(emails[1])

        results = @business.email_eligible_domain_user_emails_for(@org1, @member1).map(&:email)
        assert_equal [emails[0]], results
      end

      test "with email verification enabled, returns empty array for user without verified or approved domain emails" do
        domain = create(:verifiable_domain, owner: @business, verified: true)
        emails = ["email@#{domain.domain}", "address@not-#{domain.domain}"]
        @member1.add_email(emails[1]).verify!   # add and verify a non-domain email
        @member1.add_email(emails[0])           # add a domain email, but don't verify

        assert_empty @business.email_eligible_domain_user_emails_for(@org1, @member1)
      end
    else
      test "with email verification disabled, does not restrict to only verified emails" do
        domain = create(:verifiable_domain, owner: @business, verified: true)
        emails = ["email@#{domain.domain}", "address@#{domain.domain}"]
        @member1.add_email(emails[0])
        @member1.add_email(emails[1])

        results = @business.email_eligible_domain_user_emails_for(@org1, @member1).map(&:email)
        assert_same_elements [emails[0], emails[1]], results
      end
    end

    test "returns empty array if user is not a member of org" do
      non_member = create(:user)
      domain = create(:verifiable_domain, owner: @org1, verified: true)
      non_member.add_email("email@#{domain.domain}").verify!

      assert_empty @business.email_eligible_domain_user_emails_for(@org1, non_member)
    end

    test "returns empty array for org without verified or approved domains" do
      emails = ["olivia@sombra.example.com", "orisa@mercy.example.com", "mercy@example.com"]
      emails.each { |email| @member1.add_email(email).verify! }

      assert_empty @business.email_eligible_domain_user_emails_for(@org1, @member1)
    end

    test "returns empty array if org doesn't belong to the business" do
      rando_org = create(:organization)
      rando_org.add_member(@member1)
      domain = create(:verifiable_domain, owner: rando_org, verified: true)
      @member1.add_email("email@#{domain.domain}").verify!

      assert_empty @business.email_eligible_domain_user_emails_for(rando_org, @member1)
    end
  end
end
