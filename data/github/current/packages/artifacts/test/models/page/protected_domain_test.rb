# typed: true
# frozen_string_literal: true

require "test_helper"

class PageProtectedDomainTest < GitHub::TestCase
  include PageHelper

  fixtures do
    @user   = create(:user)
    @github = create(:organization, login: "github")

    @org = create(:business_plus_org)
    @business = create(:business, organizations: [@org])

    @project_page       = create :built_page
    @cname_user_page    = create :user_page, :built, cname: "user-page.com", owner: @user
    @cname_project_page = create :built_page, cname: "project-page.com"

    @github_owned_page  = create :built_page, owner: @github
    @github_dotcom_page = create :built_page, owner: @github, cname: "pages.github.com"

    @domain_name = "treat.com"
    @domain = create(:protected_domain, owner: @org, name: @domain_name)

    @user_domain_name = "user-dd.com"
    @user_domain = create(:protected_domain, owner: @user, name: @user_domain_name)
  end

  setup do
    mock_dns(mock_response: GitHub::Pages::Success.new(value: true))
  end

  context "dotcom" do

    test "belongs to a user-typed owner", skip_enterprise: true do
      protected_domain = Page::ProtectedDomain.new
      protected_domain.owner_id = @user.id
      protected_domain.owner_type = @user.type
      protected_domain.name = @cname_user_page.cname

      assert protected_domain.owner.type == "User"
      assert protected_domain.save
      refute_nil protected_domain.challenge
    end

    test "belongs to a org-typed owner", skip_enterprise: true do
      protected_domain = Page::ProtectedDomain.new
      protected_domain.owner = @github
      protected_domain.name = @github_dotcom_page.cname

      assert protected_domain.owner.type == "Organization"
      assert protected_domain.save
    end

    test "belongs to an enterprise-typed owner" do
      skip
    end

    test "raises when homograph attack detected" do
      protected_domain = Page::ProtectedDomain.create(owner: @github, name: "exаmple.com") # The 'a' is a cyrillic character
      refute protected_domain.valid?
      assert_equal protected_domain.errors.full_messages, ["Domain is not eligible for verification, as it is a potential homograph.", "Domain is not properly formatted."]
    end

    test "raises when invalid public domain suffix detected" do
      %w[test localhost].each do |domain|
        protected_domain = Page::ProtectedDomain.create(owner: @github, name: domain)
        refute protected_domain.valid?
        assert_equal protected_domain.errors.full_messages, ["Domain is not a valid public domain.", "Domain is not properly formatted."]
      end
    end

    test "raises when www prefix is detected" do
      ["www.github.com", "www.test.com", "www.wikipedia.fr"].each do |domain|
        protected_domain = Page::ProtectedDomain.create(owner: @github, name: domain)
        refute protected_domain.valid?
        assert_equal protected_domain.errors.full_messages, ["Domain cannot start with a 'www' prefix. Verify your root domain instead."]
      end
    end

    test "raises when github.io is detected" do
      ["username.github.io", "test.github.io"].each do |domain|
        protected_domain = Page::ProtectedDomain.create(owner: @github, name: domain)
        refute protected_domain.valid?
        assert_equal protected_domain.errors.full_messages, ["Domain cannot end with github.io."]
      end
    end

    test "raises when invalid name is detected" do
      ["username.github.io/", "test.com/"].each do |domain|
        protected_domain = Page::ProtectedDomain.create(owner: @github, name: domain)
        refute protected_domain.valid?
        assert_equal protected_domain.errors.full_messages, ["Domain is not properly formatted."]
      end
    end

    test "raises when ipv4 address is detected" do
      ["0.0.0.0", "1.1.1.1"].each do |domain|
        protected_domain = Page::ProtectedDomain.create(owner: @github, name: domain)
        refute protected_domain.valid?
        assert_equal protected_domain.errors.full_messages, ["Domain cannot be an ip address."]
      end
    end

    test "raises when ipv6 address is detected" do
      ["2001:0db8:85a3:0000:0000:8a2e:0370:7334", "0000:0db8:85a3:0000:0000:8a2e:0370:0000"].each do |domain|
        protected_domain = Page::ProtectedDomain.create(owner: @github, name: domain)
        refute protected_domain.valid?
        assert_equal protected_domain.errors.full_messages, ["Domain is not a valid public domain.", "Domain is not properly formatted.", "Domain cannot be an ip address."]
      end
    end

    test "generates a dns txt key with no environment modifier" do
      org_name = @github.login
      protected_domain = Page::ProtectedDomain.create(owner: @github, name: "example.com")

      assert_equal "_github-pages-challenge-#{org_name}.example.com", protected_domain.dns_txt_key
      assert_equal "_github-pages-challenge-#{org_name}", protected_domain.dns_txt_key_copy_challenge
    end

    test "sets pending domain protection for associated pages when verified", skip_enterprise: true do
      GitHub.flipper[:pages_protected_domains_immediately_disassociate].enable

      protected_domain = Page::ProtectedDomain.create(
        owner_id: @user.id,
        owner_type: @user.type,
        name: @cname_user_page.cname,
        state: :pending,
      )

      assert_enqueued_jobs(1, only: Pages::ClearMatchingPageCnamesJob) do
        protected_domain.state = :verified
        protected_domain.save!

        assert_enqueued_with(job: Pages::ClearMatchingPageCnamesJob, args: [
          protected_domain: protected_domain,
        ])
      end
    end

    test "deletes owner's matching page cnames when unverified", skip_enterprise: true do
      protected_domain = Page::ProtectedDomain.create(
        owner: @user,
        name: @cname_user_page.cname,
        state: :verified,
      )
      assert_enqueued_with(job: Pages::DeleteProtectedDomainJob, args: [domain_name: @cname_user_page.cname, owner: @user]) do
        protected_domain.state = :unverified
        protected_domain.save!
      end
    end

    test "does not cause any side effects when initially created in unverified state", skip_enterprise: true do
      GitHub.flipper[:pages_protected_domains_immediately_disassociate].enable

      assert_no_enqueued_jobs(only: [Pages::ClearMatchingPageCnamesJob, Pages::DeleteProtectedDomainJob]) do
        protected_domain = Page::ProtectedDomain.create(
          owner: @user,
          name: @cname_user_page.cname
        )
        assert_predicate protected_domain, :unverified?
      end
    end

    test "identifies parent domains for various edge cases" do
      cases = [
        { domain: "pages.github.com", parent_domain: "github.com" },
        { domain: "subdomain.co.uk", parent_domain: nil },
        { domain: "a.b.co.uk", parent_domain: "b.co.uk" },
        { domain: "a.b.c.d.e.f.g.dev", parent_domain: "b.c.d.e.f.g.dev" },
        { domain: ".com", parent_domain: nil },
        { domain: "com", parent_domain: nil },
      ]
      cases.each do |c|
        protected_domain = Page::ProtectedDomain.create(
          owner_id: @user.id,
          owner_type: @user.type,
          name: c[:domain],
        )
        if c[:parent_domain].nil?
          assert_nil protected_domain.parent_domain
        else
          assert_equal protected_domain.parent_domain, c[:parent_domain]
        end
      end
    end

    test "identifies subdomains of a protected domain", skip_enterprise: true do

      domain = @cname_user_page.cname

      5.times do |i|

        subdomain = i.to_s + "." + domain
        protected_subdomain = Page::ProtectedDomain.create(
          owner_id: @user.id,
          owner_type: @user.type,
          name: subdomain,
          state: :verified,
        )

      end

      protected_domain = Page::ProtectedDomain.create(
        owner_id: @user.id,
        owner_type: @user.type,
        name: @cname_user_page.cname,
        state: :verified,
      )

      assert_equal 5,
        Page::ProtectedDomain.where(parent_domain: protected_domain.name).count

    end

    test "domain is a apex domain" do
      protected_domain = Page::ProtectedDomain.create(owner: @github, name: "exаmple.com")
      assert_equal protected_domain.name, protected_domain.domain_string_for_challenge
    end

    test "domain is not an apex domain" do
      protected_domain = Page::ProtectedDomain.create(owner: @github, name: "test.exаmple.com")
      refute_equal protected_domain.name, protected_domain.domain_string_for_challenge
      assert_equal protected_domain.domain_string_for_challenge, "exаmple.com"
    end

  end

  context "verify" do
    test "organization : dns record exists" do
      assert @domain.verify
      assert_equal :verified , @domain.current_state
    end

    test "organization : pending state, if verified domain does not have a txt record anymore" do
      skip
    end

    test "organization : verify fails if dns txt record not found" do
      mock_dns(mock_response: GitHub::Pages::Failure.new(
        error: GitHub::Pages::DnsResolver::TokenNotFoundError.new))

      name = "abc.com"
      verified_domain = create(:protected_domain, owner: @org, name: name)
      assert_equal  false, verified_domain.verify
      assert_equal ["We couldn't find the TXT record. Note that DNS changes can take up to 24 hours."], verified_domain.errors.full_messages
    end

    test "user: dns record exists" do
      assert @user_domain.verify
      assert_equal :verified , @user_domain.current_state
    end

    test "user: pending state, if verified domain does not have a txt record anymore" do
      skip
    end

    test "user: verify fails if dns txt record not found" do
      mock_dns(mock_response: GitHub::Pages::Failure.new(
        error: GitHub::Pages::DnsResolver::TokenNotFoundError.new))

      name = "abc.com"
      verified_domain = create(:protected_domain, owner: @user, name: name)
      verified_domain.reload
      assert_equal  false, verified_domain.verify
      assert_equal ["We couldn't find the TXT record. Note that DNS changes can take up to 24 hours."], verified_domain.errors.full_messages
    end

    test "promotes a domain to 'verified' state" do
      domain = create(:protected_domain, :pending, owner: @user)

      assert_equal true, domain.verify
      domain.reload
      assert domain.verified?
      assert_nil domain.unverified_at
    end

    test "demotes a previously verified domain to 'pending' state" do
      mock_dns(mock_response: GitHub::Pages::Failure.new(
        error: GitHub::Pages::DnsResolver::TokenNotFoundError.new))

      domain = create(:protected_domain, :verified, owner: @user)

      assert_equal false, domain.verify
      domain.reload
      assert domain.pending?
      assert domain.unverified_at.present?
    end

    test "demotes a pending domain to 'unverified' state when the grace period has passed" do
      Timecop.freeze(Time.parse("2021-09-01T11:25Z")) do
        mock_dns(mock_response: GitHub::Pages::Failure.new(
          error: GitHub::Pages::DnsResolver::TokenNotFoundError.new))

        domain = create(:protected_domain, :pending, owner: @user, unverified_at: 1.second.ago)

        assert_equal false, domain.verify
        domain.reload
        assert domain.unverified?
        assert_nil domain.unverified_at
      end
    end

    test "ignores a pending domain that is within the grace period" do
      Timecop.freeze(Time.parse("2021-09-01T11:25Z")) do
        mock_dns(mock_response: GitHub::Pages::Failure.new(
          error: GitHub::Pages::DnsResolver::TokenNotFoundError.new))

        domain = create(:protected_domain, :pending, owner: @user, unverified_at: 1.second.from_now)

        assert_equal false, domain.verify
        domain.reload
        assert domain.pending?
      end
    end

    test "when pending and unverified_at is nil, sets unverified to 7 days in the future" do
      Timecop.freeze(Time.parse("2021-09-01T11:25Z")) do
        mock_dns(mock_response: GitHub::Pages::Failure.new(
          error: GitHub::Pages::DnsResolver::TokenNotFoundError.new))

        domain = create(:protected_domain, :pending, owner: @user, unverified_at: nil)

        assert_equal false, domain.verify
        domain.reload
        assert domain.pending?
        assert_equal 7.days.from_now, domain.unverified_at
      end
    end

    test "Only remove protected domains owned by the user" do
      user1 = create(:user)
      user2 = create(:user)
      name = "text.com"
      domain1 = create(:protected_domain, :verified, owner: user1, name: name)
      domain2 = create(:protected_domain, :verified, owner: user2, name: name)

      assert domain1 , Page::ProtectedDomain.select { |d| d.name == domain1.name && d.owner == user1 }
      assert domain2 , Page::ProtectedDomain.select { |d| d.name == domain2.name && d.owner == user2 }

      assert_enqueued_jobs 1, only: Pages::DeleteProtectedDomainJob do
        domain1.destroy
      end
    end

    test "Checks a domain in pending that is delete and another user has it verified" do
      user1 = create(:user)
      user2 = create(:user)
      d_name = "text.com"
      domain1 = create(:protected_domain, :pending, owner: user1, name: d_name)
      domain2 = create(:protected_domain, :verified, owner: user2, name: d_name)

      assert domain1 , Page::ProtectedDomain.select { |d| d.name == domain1.name && d.owner == user1 }
      assert domain2 , Page::ProtectedDomain.select { |d| d.name == domain2.name && d.owner == user2 }

      assert_enqueued_jobs 1, only: Pages::DeleteProtectedDomainJob do
        domain1.destroy
      end
    end

    test "If domain is unverfied just delete without queuing a job" do
      name = "wewe.com"
      domain = create(:protected_domain, :unverified, owner: @user, name: name)
      assert_no_enqueued_jobs(only: Pages::DeleteProtectedDomainJob) do
        domain.destroy
      end
      assert_empty Page::ProtectedDomain.select { |d| d.name == domain.name && d.owner == @user }
    end
  end

  context "#for_verification_scan", skip_enterprise: true do
    test "returns domain that have been verified over 7 days ago" do
      Timecop.freeze(Time.parse("2021-08-18T15:25Z")) do
        create(:protected_domain, :unverified)
        create(:protected_domain, :verified)
        create(:protected_domain, :verified, last_verified_at: 6.days.ago)
        create(:protected_domain, :pending)

        expected_results = [
          create(:protected_domain, :verified, last_verified_at: 7.days.ago),
          create(:protected_domain, :verified, last_verified_at: 8.days.ago)
        ]

        assert_same_elements expected_results, Page::ProtectedDomain.for_verification_scan
      end
    end
  end

  context "#for_pending_verification_scan", skip_enterprise: true do
    test "returns domains that are pending and unverified at or before now" do
      Timecop.freeze(Time.parse("2021-08-24T15:25Z")) do
        create(:protected_domain, :unverified, name: "unverified.example.org", unverified_at: 1.day.ago)
        create(:protected_domain, :pending, name: "pending2.example.org", unverified_at: 1.second.after)
        create(:protected_domain, :verified, name: "verified.example.org")

        expected_results = [
          create(:protected_domain, :pending, name: "pending.example.org", unverified_at: 8.days.ago),
          create(:protected_domain, :pending, name: "pending2.example.org", unverified_at: Time.current)
        ]

        assert_same_elements expected_results, Page::ProtectedDomain.for_pending_verification_scan
      end
    end

    test "returns domains that are pending and unverified at is somehow nil" do
      Timecop.freeze(Time.parse("2021-08-24T15:25Z")) do
        create(:protected_domain, :unverified, name: "unverified.example.org", unverified_at: 1.day.ago)
        create(:protected_domain, :pending, name: "pending2.example.org", unverified_at: 1.second.after)
        create(:protected_domain, :verified, name: "verified.example.org")

        expected_results = [
          create(:protected_domain, :pending, name: "pending.example.org", unverified_at: nil)
        ]

        assert_equal expected_results, Page::ProtectedDomain.for_pending_verification_scan
      end
    end
  end

  context "#verified!", skip_enterprise: true do
    test "sets state to verified" do
      Timecop.freeze(Time.parse("2021-08-25T08:33Z")) do
        domain = ::FactoryBot.create(:protected_domain, :pending, name: @cname_user_page.cname, owner: @cname_user_page.owner)
        assert Page.where(cname: domain.name).exists?
        domain.verified!

        domain.reload

        assert domain.verified?
        assert_equal domain.last_verified_at, Time.current
        refute domain.unverified_at
      end
    end

    test "enqueues a job to unpublish other users' pages on this domain" do
      GitHub.flipper[:pages_protected_domains_immediately_disassociate].enable
      domain = create(:protected_domain, :unverified)

      assert_enqueued_jobs(1, only: Pages::ClearMatchingPageCnamesJob) do
        domain.verified!

        assert_enqueued_with(job: Pages::ClearMatchingPageCnamesJob, args: [
          protected_domain: domain
        ])
      end
    end
  end

  context "#unverified!", skip_enterprise: true do
    test "sets state to unverified" do
      Timecop.freeze(Time.parse("2021-08-25T08:33Z")) do
        domain = ::FactoryBot.create(:protected_domain, :pending, name: @cname_user_page.cname, owner: @cname_user_page.owner)
        assert_enqueued_jobs 1, only: Pages::DeleteProtectedDomainJob do
          domain.unverified!
        end

        domain.reload

        assert domain.unverified?
        refute domain.unverified_at
      end
    end
  end

  context "#pending!", skip_enterprise: true do
    test "sets state to pending" do
      Timecop.freeze(Time.parse("2021-09-01T08:33Z")) do
        domain = ::FactoryBot.create(:protected_domain, :verified, name: @cname_user_page.cname, owner: @cname_user_page.owner)
        assert_no_enqueued_jobs(only: Pages::DeleteProtectedDomainJob) do
          domain.pending!
        end

        domain.reload

        assert domain.pending?
        assert_equal Time.parse("2021-09-08T08:33Z"), domain.unverified_at
      end
    end
  end

  context "ghes" do
    test "generates a dns txt key with a ghes environment modifier" do
      skip #TODO we dont have custom domain in GHES. So we shouldnt enable this feature in GHES
    end
  end
end
