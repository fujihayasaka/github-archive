# typed: true
# frozen_string_literal: true

require "test_helper"

class VerifiableDomainTest < GitHub::TestCase
  fixtures do
    @rando = create :user
    @site_admin = create :staff_admin_user

    @org = create(:business_plus_org)
    @business = create(:business, organizations: [@org])
    @business_owner = @business.owners.first
    @business_billing_manager = create :user
    @business.billing.add_manager @business_billing_manager, actor: @business_owner
    @business_domain_name = "enterprise.lol"
    @business_domain = create :verifiable_domain, owner: @business, domain: @business_domain_name
    create(:verifiable_domain, owner: @org, verified: true)
    @org.reload.enable_notification_restrictions(actor: @org.admin)

    @organization = create :business_plus_organization
    @organization_admin = @organization.admin
    @organization_billing_manager = create :user
    @organization.billing.add_manager @organization_billing_manager, actor: @organization_admin

    @domain_name = "www.github.com"
    @domain = create(:verifiable_domain, owner: @organization, domain: @domain_name)

    @state_verified = "verified"
    @state_approved = "approved"
    @txt_env_modifier = TestEnv.test_in_multitenancy_mode? ? "ghe-" : ""
  end

  setup do
    GitHub.heaven_env_reset
    reset_monolith_redis_rate_limiter
  end

  context "Resolv::DNS::Config.parse_resolv_conf" do
    test "filters out any nameservers that are IPv6 link-local addresses" do
      parsed = Resolv::DNS::Config.parse_resolv_conf \
        Rails.root.join("test/fixtures/verifiable_domains/example-resolv.conf")

      assert_same_elements \
        [
          "8.8.8.8",
          "127.0.0.1",
          "10.0.1.1",
          "fe80::5cb0:3cff:fe51:29b0",
          "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
          "github.com"
        ],
        parsed[:nameserver]
    end
  end

  context "#destroy" do
    test "removes verification token" do
      refute_nil @domain.verification_token
      kv_key = @domain.token_key

      @domain.destroy

      assert_nil VerifiableDomain.find_by id: @domain.id
      assert_nil GitHub.kv.get(kv_key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
    end
  end

  context "#authoritative_nameservers" do
    test "uses default nameservers for verification if no nameservers are found" do
      mock_dns_setup # The test setup returns no nameservers
      assert_equal Resolv::DNS::Config.default_config_hash[:nameserver], @domain.authoritative_nameservers
    end

    test "handles DNS query timeout gracefully" do
      mock_dns_setup
      Resolv::DNS.any_instance.stubs(:getresources).with(@domain_name, Resolv::DNS::Resource::IN::NS).raises(Resolv::ResolvTimeout)
      assert_equal \
        Resolv::DNS::Config.default_config_hash[:nameserver],
        @domain.authoritative_nameservers
    end

    test "specifies found nameservers first if nameservers are found" do
      nameserver1 = mock("nameserver1")
      nameserver2 = mock("nameserver2")
      [nameserver1, nameserver2].each do |server|
        server.stubs(:name).returns("I'm a nameserver")
        server.stubs(:is_a?).returns(Resolv::DNS::Resource::IN::NS)
      end

      Resolv::DNS.any_instance.stubs(:getresources).with(@domain_name, Resolv::DNS::Resource::IN::NS).returns([nameserver1, nameserver2])
      default_resolver = @domain.default_resolver

      expected_nameservers = [
          "I'm a nameserver",
          "I'm a nameserver",
          Resolv::DNS::Config.default_config_hash[:nameserver],
        ].flatten

      mock_resolver = mock("resolver")
      mock_resolver.stubs(:timeouts=)
      Resolv::DNS.stubs(:new).with(nameserver: expected_nameservers).returns(mock_resolver)

      refute_equal default_resolver, @domain.dns_resolver
      assert_equal mock_resolver, @domain.dns_resolver
      assert_equal expected_nameservers, @domain.authoritative_nameservers
    end
  end

  context "#verify" do
    test "succeeds when the expected DNS record exists" do
      mock_dns_setup
      mock_dns_verification

      assert @domain.verify(actor: @organization_admin)
      assert @domain.verified?
      assert_nil @domain.verification_token
    end

    test "succeeds when the domain has been approved previously" do
      mock_dns_setup
      mock_dns_verification

      assert @domain.approve(actor: @organization_admin)
      assert @domain.verify(actor: @organization_admin)
      assert @domain.verified?
      assert @domain.approved?
      assert_nil @domain.verification_token
    end

    if GitHub.single_business_environment?
      test "enqueues domain verification notice job for single business environment Organization owner" do
        mock_dns_setup
        mock_dns_verification

        assert_enqueued_with(job: DomainVerificationNoticeJob,
                             args: [@organization, @domain.domain, @state_verified]) do
          assert @domain.verify(actor: @organization_admin)
        end
      end
    else
      test "enqueues domain verification notice job for business plus plan Organization owner" do
        assert_equal GitHub::Plan::BUSINESS_PLUS, @organization.plan_name

        mock_dns_setup
        mock_dns_verification

        assert_enqueued_with(job: DomainVerificationNoticeJob,
                             args: [@organization, @domain.domain, @state_verified]) do
          assert @domain.verify(actor: @organization_admin)
        end
      end

      test "does not enqueue domain verification notice job for business plan Organization owner", skip_in_multitenant_mode: true do
        @organization.update! plan: GitHub::Plan::BUSINESS

        mock_dns_setup
        mock_dns_verification

        assert_enqueued_jobs 0, only: DomainVerificationNoticeJob do
          assert @domain.verify(actor: @organization_admin)
        end
      end

      test "does not enqueue domain verification notice job for free plan Organization owner", skip_in_multitenant_mode: true do
        @organization.update! plan: GitHub::Plan::FREE

        mock_dns_setup
        mock_dns_verification

        assert_enqueued_jobs 0, only: DomainVerificationNoticeJob do
          assert @domain.verify(actor: @organization_admin)
        end
      end
    end

    test "enqueues job to instrument verifying a profile domain for an Organization owner" do
      mock_dns_setup
      mock_dns_verification

      assert_enqueued_with(job: InstrumentProfileDomainVerifiedJob,
                           args: [@domain, @organization_admin]) do
        assert @domain.verify(actor: @organization_admin)
      end
    end

    test "succeeds for a business owned domain when the expected DNS record exists" do
      mock_dns_setup(domain_name: @business_domain.domain)
      mock_dns_verification(
        verification_token: @business_domain.verification_token,
        dns_record_url: @business_domain.dns_host_name
      )

      assert @business_domain.verify(actor: @business_owner)
      assert @business_domain.verified?
      assert_nil @business_domain.verification_token
    end

    test "enqueues domain verification notice job for Business owner not downgraded to a free plan" do
      refute_predicate @business, :downgraded_to_free_plan?

      mock_dns_setup(domain_name: @business_domain.domain)
      mock_dns_verification(
        verification_token: @business_domain.verification_token,
        dns_record_url: @business_domain.dns_host_name
      )

      assert_enqueued_with(job: DomainVerificationNoticeJob,
                           args: [@business, @business_domain.domain, @state_verified]) do
        assert @business_domain.verify(actor: @business_owner)
      end
    end

    test "does not enqueue domain verification notice job for Business owner downgraded to a free plan", skip_enterprise: true, skip_in_multitenant_mode: true do
      @business.downgrade_to_free_plan

      mock_dns_setup(domain_name: @business_domain.domain)
      mock_dns_verification(
        verification_token: @business_domain.verification_token,
        dns_record_url: @business_domain.dns_host_name
      )

      assert_enqueued_jobs 0, only: DomainVerificationNoticeJob do
        assert @business_domain.verify(actor: @business_owner)
      end
    end

    test "enqueues job to instrument verifying a profile domain for a Business owner" do
      mock_dns_setup(domain_name: @business_domain.domain)
      mock_dns_verification(
        verification_token: @business_domain.verification_token,
        dns_record_url: @business_domain.dns_host_name
      )

      assert_enqueued_with(job: InstrumentProfileDomainVerifiedJob,
                           args: [@business_domain, @business_owner]) do
        assert @business_domain.verify(actor: @business_owner)
      end
    end

    test "succeeds even if another organization has already verified it" do
      same_domain_different_org = create(:verifiable_domain, verified: true, domain: @domain_name)
      mock_dns_setup
      mock_dns_verification

      assert @domain.verify(actor: @organization_admin)
      assert @domain.verified?
    end

    test "fails when the expected DNS record doesn't exist" do
      mock_dns_setup
      Resolv::DNS.any_instance.stubs(:getresources).with(
        @domain.dns_host_name, Resolv::DNS::Resource::IN::TXT,
      ).returns([])

      refute @domain.verify(actor: @organization_admin)
      refute @domain.verified?
      assert_equal ["We couldn't find the TXT record. Note that DNS changes can take up to 72 hours."], @domain.errors.full_messages
    end

    test "return an error message when Resolv raises an error" do
      mock_dns_setup
      Resolv::DNS.any_instance.stubs(:getresources).raises(Resolv::DNS::DecodeError)

      refute @domain.verify(actor: @organization_admin)
      refute @domain.verified?
      assert_equal ["An error occurred while verifying this DNS record."], @domain.errors.full_messages
    end

    test "fails when the expected DNS record has the wrong value" do
      mock_dns_setup

      record = mock("record")
      record.stubs(:strings).returns(["not a verification token"])
      record.stubs(:is_a?).returns(Resolv::DNS::Resource::IN::TXT)
      Resolv::DNS.any_instance.stubs(:getresources).with(
        @domain.dns_host_name, Resolv::DNS::Resource::IN::TXT,
      ).returns([record])

      refute @domain.verify(actor: @organization_admin)
      refute @domain.verified?
      assert_equal ["The TXT record did not match the verification code. Note that DNS changes can take up to 72 hours."], @domain.errors.full_messages
    end

    test "fails when the DNS query attempt times out" do
      mock_dns_setup
      Resolv::DNS.any_instance.stubs(:getresources).raises(Resolv::ResolvTimeout)

      refute @domain.verify(actor: @organization_admin)
      refute @domain.verified?
      assert_equal ["An error occurred while verifying this DNS record."], @domain.errors.full_messages
    end

    test "fails when the domain is already verified for this organization" do
      @domain.update_attribute(:verified, true) # setting this after create so generating the token doesn't cause an error
      refute @domain.verify(actor: @organization_admin)
      assert_equal ["Domain has already been verified."], @domain.errors.full_messages
    end

    test "fails when the DNS query attempt encounters a socket error" do
      mock_dns_setup
      Resolv::DNS.any_instance.stubs(:getresources).raises(SocketError.new("getaddrinfo: Name or service not known"))

      refute @domain.verify(actor: @organization_admin)
      refute @domain.verified?
      assert_equal ["An error occurred while verifying this DNS record."], @domain.errors.full_messages
    end

    test "verifying a domain does not automatically enable notification restrictions" do
      mock_dns_setup
      mock_dns_verification

      refute @organization.restrict_notifications_to_verified_domains?
      assert @domain.verify(actor: @organization_admin)
      refute @organization.reload.restrict_notifications_to_verified_domains?
    end

    if GitHub.rate_limiting_enabled?
      test "attempts are rate limited" do
        VerifiableDomain.any_instance.stubs(:verification_dns_record_exists?).returns(false)
        VerifiableDomain.any_instance.stubs(:rate_limit_increment).returns(stub(at_limit?: true))

        @domain.verify(actor: @organization_admin)
        assert_equal ["You've reached the maximum number of verification attempts. Please try again later."], @domain.errors.full_messages
      end
    end
  end

  context "#unverify" do
    test "succeeds if the domain is already verified" do
      @domain.update_attribute(:verified, true)
      assert @domain.verified?

      assert @domain.unverify(actor: @organization_admin)
      refute @domain.verified?
      assert_nil @domain.verification_token
    end

    test "fails if the domain is not yet verified" do
      refute @domain.verified?
      refute @domain.unverify(actor: @organization_admin)
      refute @domain.verified? # still not verified
    end

    test "fails if it is the sole verified domain and notification restrictions are enabled" do
      domain = create(:verifiable_domain, owner: @organization)
      assert domain.update(verified: true)

      assert_equal 1, @organization.verifiable_domains.verified.count
      assert @organization.enable_notification_restrictions(actor: @organization.admin)
      assert @organization.restrict_notifications_to_verified_domains?
      refute domain.unverify(actor: @organization_admin)
      assert_equal ["Cannot unverify a domain that is required to enforce an organization policy."], domain.errors.full_messages
    end
  end

  context "#approve" do
    test "approve unverified domain" do
      assert @domain.approve(actor: @organization_admin)
      assert @domain.approved?
      refute @domain.verified?
      refute_nil @domain.verification_token
    end

    test "approve verified domain" do
      mock_dns_setup
      mock_dns_verification

      assert @domain.verify(actor: @organization_admin)
      assert @domain.verified?

      assert @domain.approve(actor: @organization_admin)
      assert @domain.approved?
      assert @domain.verified?
    end

    test "fails to approve approved domain" do
      assert @domain.approve(actor: @organization_admin)
      assert @domain.approved?
      refute @domain.approve(actor: @organization_admin)
      assert_equal ["Domain has already been approved."], @domain.errors.full_messages
    end

    if VerifiableDomain.approved_domain_emails_visible_to_admins?
      test "enqueues the domain verification notice job for an Organization owner" do
        assert_enqueued_with(job: DomainVerificationNoticeJob,
                            args: [@organization, @domain.domain, @state_approved]) do
          assert @domain.approve(actor: @organization_admin)
        end
      end

      test "enqueues the domain verification notice job for a Business owner" do
        assert_enqueued_with(job: DomainVerificationNoticeJob,
                            args: [@business, @business_domain.domain, @state_approved]) do
          assert @business_domain.approve(actor: @business_owner)
        end
      end
    end
  end

  context "#adminable_by?" do
    context "with organization owner" do
      test "returns true for org admins" do
        assert @domain.adminable_by?(@organization_admin)
      end

      test "returns false for org billing managers" do
        refute @domain.adminable_by?(@organization_billing_manager)
      end

      test "returns false for randos" do
        refute @domain.adminable_by?(@rando)
      end

      test "returns false if viewer is nil" do
        refute @domain.adminable_by?(nil)
      end

      test "returns false for a site admin if they are not an admin" do
        refute @domain.adminable_by?(@site_admin)
      end
    end

    context "with enterprise owner" do
      test "returns true for enterprise owners" do
        assert @business_domain.adminable_by?(@business_owner)
      end

      test "returns false for enterprise billing managers" do
        refute @business_domain.adminable_by?(@business_billing_manager)
      end

      test "returns false for randos" do
        refute @business_domain.adminable_by?(@rando)
      end

      test "returns false if viewer is nil" do
        refute @business_domain.adminable_by?(nil)
      end

      test "returns false for site admin if they are not an owner" do
        refute @business_domain.adminable_by?(@site_admin)
      end
    end
  end

  context "intializers and validations" do
    test "domain cannot exceed 255 characters" do
      domain = build :verifiable_domain, domain: %Q[#{"e" * 300}.com]
      refute_predicate domain, :valid?
      assert_includes domain.errors[:domain], "is too long (maximum is 255 characters)"
    end

    test "domain must be unicode3" do
      domain = build :verifiable_domain, domain: "🍿.jdenn.es"
      refute_predicate domain, :valid?
      assert_includes domain.errors[:domain], "doesn't accept 4-byte Unicode"
    end

    test "normalizes domain name" do
      domain = create(:verifiable_domain, domain: "www.example.com")
      assert domain.valid?
      assert_equal domain.domain, "www.example.com"
      domain = create(:verifiable_domain, domain: "http://www.example.com")
      assert domain.valid?
      assert_equal domain.domain, "www.example.com"

      domain = create(:verifiable_domain, domain: "https://www.example.com")
      assert domain.valid?
      assert_equal domain.domain, "www.example.com"

      domain = create(:verifiable_domain, domain: "https://www.subdomain.example.com")
      assert domain.valid?
      assert_equal domain.domain, "www.subdomain.example.com"

      domain = create(:verifiable_domain, domain: "ExAMpLe.cOm")
      assert domain.valid?
      assert_equal domain.domain, "example.com"

      domain = create(:verifiable_domain, domain: "example.com/foo")
      assert domain.valid?
      assert_equal domain.domain, "example.com"

      domain = create(:verifiable_domain, domain: "foo:bar@example.com")
      assert domain.valid?
      assert_equal domain.domain, "example.com"

      domain = create(:verifiable_domain, domain: "foo+bar/public@example.com")
      assert domain.valid?
      assert_equal domain.domain, "example.com"
    end

    # Some users of `normalize_domain`, eg `Organization::async_verified_profile_domains` call it directly on strings
    # without creating a VerifiableDomain object and thus miss the validation. This allows invalid domains to be set.
    # This test ensures that `normalize_domain` returns "http://" (the fallback) for invalid domains that can't be tested otherwise.
    test "#normalize_domain" do
      assert_equal VerifiableDomain.normalize_domain(""), "http://"
      assert_equal VerifiableDomain.normalize_domain("@@@"), "http://"
      assert_equal VerifiableDomain.normalize_domain("example@"), "http://"
      assert_equal VerifiableDomain.normalize_domain("@example@"), "http://"
    end

    test "returns an error if an invalid domain name is provided" do
      domain = VerifiableDomain.create(owner: @organization, domain: "WHAT EVEN AM I")
      refute domain.valid?
      assert_equal domain.errors.full_messages, ["Domain is not a valid public domain."]

      domain = VerifiableDomain.create(owner: @organization, domain: "https://www.example.this-is-not-a-valid-tld")
      refute domain.valid?
      assert_equal domain.errors.full_messages, ["Domain is not a valid public domain."]

      domain = VerifiableDomain.create(owner: @organization, domain: "www.exаmple.com") # The 'a' is a cyrillic character
      refute domain.valid?
      assert_equal domain.errors.full_messages, ["Domain is not eligible for verification, as it is a potential homograph."]

      domain = VerifiableDomain.create(owner: @organization, domain: "xn--exmple-4nf.com")
      refute domain.valid?
      assert_equal domain.errors.full_messages, ["Domain is not eligible for verification, as it is a potential homograph."]

      domain = VerifiableDomain.create(owner: @organization, domain: "@example")
      refute domain.valid?
      assert_equal domain.errors.full_messages, ["Domain is not a valid public domain."]
    end

    test "does not allow duplicate domain (case insensitive)" do
      message = "has already been claimed"

      org_domain = VerifiableDomain.new(domain: @domain_name, owner: @organization)
      refute_predicate org_domain, :valid?
      assert org_domain.errors[:domain].include? message

      org_domain = VerifiableDomain.new(domain: @domain_name.upcase, owner: @organization)
      refute_predicate org_domain, :valid?
      assert org_domain.errors[:domain].include? message
    end
  end

  context "#dns_host_name" do
    if GitHub.enterprise?
      test "returns expected result on GHES with org owner for old TXT record format" do
        org = create(:organization)
        org_name = org.display_login

        domain = create(:verifiable_domain, owner: org, domain: "example.com", created_at: Time.utc(2024, 4, 9))

        assert_equal \
          "_github-challenge-ghes-#{org_name}-org.example.com",
          domain.async_dns_host_name.sync
        assert_equal \
          "_github-challenge-ghes-#{org_name}-org.example.com",
          domain.dns_host_name
      end

      test "returns expected result on GHES with org owner for new TXT record format" do
        org = create(:organization)
        org_name = org.display_login

        domain = create(:verifiable_domain, owner: org, domain: "example.com", created_at: Time.utc(2024, 4, 11))

        assert_equal "_gh-ghes-#{org_name}-o.example.com", domain.async_dns_host_name.sync
        assert_equal "_gh-ghes-#{org_name}-o.example.com", domain.dns_host_name
      end

      test "returns expected result on GHES with enterprise owner for old TXT record format" do
        business_slug = @business.slug
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 9))

        assert_equal \
          "_github-challenge-ghes-#{business_slug}-ent.jdenn.es",
          domain.async_dns_host_name.sync
        assert_equal \
          "_github-challenge-ghes-#{business_slug}-ent.jdenn.es",
          domain.dns_host_name
      end

      test "returns expected result on GHES with enterprise owner for new TXT record format" do
        business_slug = @business.slug
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 11))

        assert_equal "_gh-ghes-#{business_slug}-e.jdenn.es", domain.async_dns_host_name.sync
        assert_equal "_gh-ghes-#{business_slug}-e.jdenn.es", domain.dns_host_name
      end

      test "returns expected result on GHES with truncated business name for old TXT record format" do
        @business.update(slug: "an-exceptionally-long-ghes-github-installation")
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 9))
        reserved_length = "_github-challenge-ghes--ent".length

        truncated_slug = @business.slug[0, (VerifiableDomain::MAX_TXT_RECORD_LENGTH - reserved_length)]
        assert_equal \
          "_github-challenge-ghes-#{truncated_slug}-ent.jdenn.es",
          domain.async_dns_host_name.sync
        assert_equal \
          "_github-challenge-ghes-#{truncated_slug}-ent.jdenn.es",
          domain.dns_host_name
      end

      test "returns expected result on GHES with truncated business name for new TXT record format" do
        @business.update(slug: "an-exceptionally-long-ghes-github-installation")
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 11))
        reserved_length = "_github-challenge-ghes--ent".length
        available_owner_param_length = VerifiableDomain::MAX_TXT_RECORD_LENGTH - "_gh-ghes-e".length

        truncated_slug = @business.slug[0, available_owner_param_length]
        assert_equal "_gh-ghes-#{truncated_slug}-e.jdenn.es", domain.async_dns_host_name.sync
        assert_equal "_gh-ghes-#{truncated_slug}-e.jdenn.es", domain.dns_host_name
      end
    elsif TestEnv.test_in_multitenancy_mode?
      test "returns expected result on Proxima with org owner for old TXT record format" do
        org = create(:organization)
        org_name = org.display_login

        domain = create(:verifiable_domain, owner: org, domain: "example.com", created_at: Time.utc(2024, 4, 9))

        assert_equal \
          "_github-challenge-ghe-#{org_name}-org.example.com",
          domain.async_dns_host_name.sync
        assert_equal \
          "_github-challenge-ghe-#{org_name}-org.example.com",
          domain.dns_host_name
      end

      test "returns expected result on Proxima with org owner for new TXT record format" do
        org = create(:organization)
        org_name = org.display_login

        domain = create(:verifiable_domain, owner: org, domain: "example.com", created_at: Time.utc(2024, 4, 11))

        assert_predicate domain, :use_new_txt_record_format?
        assert_equal "_gh-ghe-#{org_name}-o.example.com", domain.async_dns_host_name.sync
        assert_equal "_gh-ghe-#{org_name}-o.example.com", domain.dns_host_name
      end

      test "returns expected result on Proxima with enterprise owner for old TXT record format" do
        business_slug = @business.slug
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 9))

        assert_equal \
          "_github-challenge-ghe-#{business_slug}-ent.jdenn.es",
          domain.async_dns_host_name.sync
        assert_equal \
          "_github-challenge-ghe-#{business_slug}-ent.jdenn.es",
          domain.dns_host_name
      end

      test "returns expected result on Proxima with enterprise owner for new TXT record format" do
        business_slug = @business.slug
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 11))

        assert_predicate domain, :use_new_txt_record_format?
        assert_equal "_gh-ghe-#{business_slug}-e.jdenn.es", domain.async_dns_host_name.sync
        assert_equal "_gh-ghe-#{business_slug}-e.jdenn.es", domain.dns_host_name
      end

      test "returns expected result on Proxima with configured Heaven environment for old TXT record format" do
        business_slug = @business.slug
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 9))

        assert_equal \
          "_github-challenge-ghe-#{business_slug}-ent.jdenn.es",
          domain.async_dns_host_name.sync
        assert_equal \
          "_github-challenge-ghe-#{business_slug}-ent.jdenn.es",
          domain.dns_host_name
      end

      test "returns expected result on Proxima with truncated business name for old TXT record format" do
        @business.update(slug: "an-exceptionally-long-ghes-github-installation")
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 9))
        reserved_length = "_github-challenge-ghe--ent".length

        truncated_slug = @business.slug[0, (VerifiableDomain::MAX_TXT_RECORD_LENGTH - reserved_length)]
        assert_equal \
          "_github-challenge-ghe-#{truncated_slug}-ent.jdenn.es",
          domain.async_dns_host_name.sync
        assert_equal \
          "_github-challenge-ghe-#{truncated_slug}-ent.jdenn.es",
          domain.dns_host_name
      end

      test "returns expected result on Proxima with truncated business name for new TXT record format" do
        @business.update(slug: "an-exceptionally-long-ghes-github-installation")
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 11))
        available_owner_param_length = VerifiableDomain::MAX_TXT_RECORD_LENGTH - "_gh-ghe-e".length

        truncated_slug = @business.slug[0, available_owner_param_length]
        assert_predicate domain, :use_new_txt_record_format?
        assert_equal "_gh-ghe-#{truncated_slug}-e.jdenn.es", domain.async_dns_host_name.sync
        assert_equal "_gh-ghe-#{truncated_slug}-e.jdenn.es", domain.dns_host_name
      end
    else
      test "returns expected result on dotcom with org owner for old TXT record format" do
        org = create(:organization)
        org_name = org.login

        domain = create(:verifiable_domain, owner: org, domain: "example.com", created_at: Time.utc(2024, 4, 9))

        assert_equal \
          "_github-challenge-#{@txt_env_modifier}#{org_name}-org.example.com",
          domain.async_dns_host_name.sync
        assert_equal \
          "_github-challenge-#{@txt_env_modifier}#{org_name}-org.example.com",
          domain.dns_host_name
      end

      test "returns expected result on dotcom with org owner for new TXT record format" do
        org = create(:organization)
        org_name = org.login

        domain = create(:verifiable_domain, owner: org, domain: "example.com", created_at: Time.utc(2024, 4, 11))

        assert_predicate domain, :use_new_txt_record_format?
        assert_equal "_gh-#{@txt_env_modifier}#{org_name}-o.example.com", domain.async_dns_host_name.sync
        assert_equal "_gh-#{@txt_env_modifier}#{org_name}-o.example.com", domain.dns_host_name
      end

      test "returns expected result on dotcom with enterprise owner for old TXT record format" do
        business_slug = @business.slug
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 9))

        assert_equal \
          "_github-challenge-#{business_slug}-ent.jdenn.es",
          domain.async_dns_host_name.sync
        assert_equal \
          "_github-challenge-#{business_slug}-ent.jdenn.es",
          domain.dns_host_name
      end

      test "returns expected result on dotcom with enterprise owner for new TXT record format" do
        business_slug = @business.slug
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 11))

        assert_predicate domain, :use_new_txt_record_format?
        assert_equal "_gh-#{business_slug}-e.jdenn.es", domain.async_dns_host_name.sync
        assert_equal "_gh-#{business_slug}-e.jdenn.es", domain.dns_host_name
      end

      test "returns expected result with subdomains for old TXT record format" do
        business_slug = @business.slug
        domain = create(
          :verifiable_domain,
          owner: @business,
          domain: "github.example.com",
          created_at: Time.utc(2024, 4, 9)
        )

        assert_equal \
          "_github-challenge-#{business_slug}-ent.github.example.com",
          domain.async_dns_host_name.sync
        assert_equal \
          "_github-challenge-#{business_slug}-ent.github.example.com",
          domain.dns_host_name
      end

      test "returns expected result with subdomains for new TXT record format" do
        business_slug = @business.slug
        domain = create(
          :verifiable_domain,
          owner: @business,
          domain: "github.example.com",
          created_at: Time.utc(2024, 4, 11)
        )

        assert_predicate domain, :use_new_txt_record_format?
        assert_equal "_gh-#{business_slug}-e.github.example.com", domain.async_dns_host_name.sync
        assert_equal "_gh-#{business_slug}-e.github.example.com", domain.dns_host_name
      end

      test "returns expected result on dotcom with a subdomain and truncated enterprise owner name for old TXT record format" do
        @business.update(slug: "an-exceptionally-long-dotcom-github-enterprise-name")
        domain = create(
          :verifiable_domain,
          owner: @business,
          domain: "github.example.com",
          created_at: Time.utc(2024, 4, 9)
        )
        reserved_length = "_github-challenge--ent.github".length

        truncated_slug = @business.slug[0, (VerifiableDomain::MAX_TXT_RECORD_LENGTH - reserved_length)]
        assert_equal \
          "_github-challenge-#{truncated_slug}-ent.github.example.com",
          domain.async_dns_host_name.sync
        assert_equal \
          "_github-challenge-#{truncated_slug}-ent.github.example.com",
          domain.dns_host_name
      end

      test "returns expected result on dotcom with a subdomain and truncated enterprise owner name for new TXT record format" do
        @business.update(slug: "an-exceptionally-long-dotcom-github-enterprise-name")
        domain = create(
          :verifiable_domain,
          owner: @business,
          domain: "github.example.com",
          created_at: Time.utc(2024, 4, 11)
        )
        available_owner_param_length = VerifiableDomain::MAX_TXT_RECORD_LENGTH - "_gh-e.github".length

        truncated_slug = @business.slug[0, available_owner_param_length]
        assert_predicate domain, :use_new_txt_record_format?
        assert_equal "_gh-#{truncated_slug}-e.github.example.com", domain.async_dns_host_name.sync
        assert_equal "_gh-#{truncated_slug}-e.github.example.com", domain.dns_host_name
      end
    end
  end

  context "#dns_txt_key_copy_challenge and #domain_string_for_challenge" do
    if GitHub.enterprise?
      test "returns expected result on GHES with org owner for old TXT record format" do
        org = create(:organization)
        org_name = org.login

        domain = create(:verifiable_domain, owner: org, domain: "example.com", created_at: Time.utc(2024, 4, 9))

        assert_equal \
          "_github-challenge-ghes-#{org_name}-org",
          domain.dns_txt_key_copy_challenge
        assert_equal "example.com", domain.domain_string_for_challenge
      end

      test "returns expected result on GHES with org owner for new TXT record format" do
        org = create(:organization)
        org_name = org.login

        domain = create(:verifiable_domain, owner: org, domain: "example.com", created_at: Time.utc(2024, 4, 11))

        assert_equal "_gh-ghes-#{org_name}-o", domain.dns_txt_key_copy_challenge
        assert_equal "example.com", domain.domain_string_for_challenge
      end

      test "returns expected result on GHES with enterprise owner for old TXT record format" do
        business_slug = @business.slug
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 9))

        assert_equal \
          "_github-challenge-ghes-#{business_slug}-ent",
          domain.dns_txt_key_copy_challenge
        assert_equal "jdenn.es", domain.domain_string_for_challenge
      end

      test "returns expected result on GHES with enterprise owner for new TXT record format" do
        business_slug = @business.slug
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 11))

        assert_equal "_gh-ghes-#{business_slug}-e", domain.dns_txt_key_copy_challenge
        assert_equal "jdenn.es", domain.domain_string_for_challenge
      end

      test "returns expected result with 63 characters or less on GHES with enterprise owner for old TXT record format" do
        @business.update(slug: "an-exceptionally-long-ghes-github-installation")
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 9))
        reserved_length = "_github-challenge-ghes--ent".length

        truncated_slug = @business.slug[0, (VerifiableDomain::MAX_TXT_RECORD_LENGTH - reserved_length)]
        assert_equal \
          "_github-challenge-ghes-#{truncated_slug}-ent",
          domain.dns_txt_key_copy_challenge
        assert_equal "jdenn.es", domain.domain_string_for_challenge
        assert VerifiableDomain::MAX_TXT_RECORD_LENGTH >= domain.dns_txt_key_copy_challenge.length
      end

      test "returns expected result with 64 characters or less on GHES with enterprise owner for new TXT record format" do
        @business.update(slug: "an-exceptionally-long-ghes-github-installation")
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 11))
        available_owner_param_length = VerifiableDomain::MAX_TXT_RECORD_LENGTH - "_gh-ghes-e".length

        truncated_slug = @business.slug[0, available_owner_param_length]
        assert_equal "_gh-ghes-#{truncated_slug}-e", domain.dns_txt_key_copy_challenge
        assert_equal "jdenn.es", domain.domain_string_for_challenge
        assert VerifiableDomain::MAX_TXT_RECORD_LENGTH >= domain.dns_txt_key_copy_challenge.length
      end
    else
      test "returns expected result on dotcom with org owner for old TXT record format" do
        org = create(:organization)
        org_name = org.display_login

        domain = create(:verifiable_domain, owner: org, domain: "example.com", created_at: Time.utc(2024, 4, 9))

        assert_equal \
          "_github-challenge-#{@txt_env_modifier}#{org_name}-org",
          domain.dns_txt_key_copy_challenge
        assert_equal "example.com", domain.domain_string_for_challenge
      end

      test "returns expected result on dotcom with org owner for new TXT record format" do
        org = create(:organization)
        org_name = org.display_login

        domain = create(:verifiable_domain, owner: org, domain: "example.com", created_at: Time.utc(2024, 4, 11))

        assert_predicate domain, :use_new_txt_record_format?
        assert_equal "_gh-#{@txt_env_modifier}#{org_name}-o", domain.dns_txt_key_copy_challenge
        assert_equal "example.com", domain.domain_string_for_challenge
      end

      test "returns expected result on dotcom with enterprise owner for old TXT record format" do
        business_slug = @business.slug
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 9))

        assert_equal \
          "_github-challenge-#{@txt_env_modifier}#{business_slug}-ent",
          domain.dns_txt_key_copy_challenge
        assert_equal "jdenn.es", domain.domain_string_for_challenge
      end

      test "returns expected result on dotcom with enterprise for new TXT record format" do
        business_slug = @business.slug
        domain = create(:verifiable_domain, owner: @business, domain: "jdenn.es", created_at: Time.utc(2024, 4, 11))

        assert_predicate domain, :use_new_txt_record_format?
        assert_equal "_gh-#{@txt_env_modifier}#{business_slug}-e", domain.dns_txt_key_copy_challenge
        assert_equal "jdenn.es", domain.domain_string_for_challenge
      end

      test "returns expected result with subdomains for old TXT record format" do
        business_slug = @business.slug
        domain = create(
          :verifiable_domain,
          owner: @business,
          domain: "github.example.com",
          created_at: Time.utc(2024, 4, 9)
        )

        assert_equal \
          "_github-challenge-#{@txt_env_modifier}#{business_slug}-ent.github",
          domain.dns_txt_key_copy_challenge
        assert_equal "example.com", domain.domain_string_for_challenge
      end

      test "returns expected result with subdomains for new TXT record format" do
        business_slug = @business.slug
        domain = create(
          :verifiable_domain,
          owner: @business,
          domain: "github.example.com",
          created_at: Time.utc(2024, 4, 11)
        )

        assert_predicate domain, :use_new_txt_record_format?
        assert_equal "_gh-#{@txt_env_modifier}#{business_slug}-e.github", domain.dns_txt_key_copy_challenge
        assert_equal "example.com", domain.domain_string_for_challenge
      end

      test "returns expected result with domain on public suffix list for old TXT record format" do
        business_slug = @business.slug
        domain = create(:verifiable_domain, owner: @business, domain: "github.io", created_at: Time.utc(2024, 4, 9))

        assert_equal \
          "_github-challenge-#{@txt_env_modifier}#{business_slug}-ent",
          domain.dns_txt_key_copy_challenge
        assert_equal "github.io", domain.domain_string_for_challenge
      end

      test "returns expected result with domain on public suffix list for new TXT record format" do
        business_slug = @business.slug
        domain = create(:verifiable_domain, owner: @business, domain: "github.io", created_at: Time.utc(2024, 4, 11))

        assert_predicate domain, :use_new_txt_record_format?
        assert_equal "_gh-#{@txt_env_modifier}#{business_slug}-e", domain.dns_txt_key_copy_challenge
        assert_equal "github.io", domain.domain_string_for_challenge
      end

      test "returns expected result with domain record size less than or equal to 63 characters for old TXT record format" do
        business = create(:business, slug: "this-is-an-exceptionally-long-business-slug-to-have")
        domain = create(:verifiable_domain, owner: business, domain: "github.io", created_at: Time.utc(2024, 4, 9))
        reserved_length = "_github-challenge--ent".length

        truncated_slug = business.slug[0, (VerifiableDomain::MAX_TXT_RECORD_LENGTH - reserved_length)]
        assert_equal "_github-challenge-#{@txt_env_modifier}#{truncated_slug}-ent", domain.dns_txt_key_copy_challenge
        assert VerifiableDomain::MAX_TXT_RECORD_LENGTH >= domain.dns_txt_key_copy_challenge.length
      end

      test "returns expected result with domain record size less than or equal to 64 characters for new TXT record format" do
        business = create(:business, slug: "this-is-an-exceptionally-long-business-slug-to-have")
        domain = create(:verifiable_domain, owner: business, domain: "github.io", created_at: Time.utc(2024, 4, 11))
        available_owner_param_length = VerifiableDomain::MAX_TXT_RECORD_LENGTH - "_gh-e".length

        truncated_slug = business.slug[0, available_owner_param_length]
        assert_predicate domain, :use_new_txt_record_format?
        assert_equal "_gh-#{@txt_env_modifier}#{truncated_slug}-e", domain.dns_txt_key_copy_challenge
        assert domain.dns_txt_key_copy_challenge.length <= 64
      end

      test "adapts to domains with subdomains to return record that is 63 characters or less for old TXT record format" do
        business = create(:business, slug: "this-is-an-exceptionally-long-business-slug-to-have")
        domain = create(
          :verifiable_domain,
          owner: business,
          domain: "github.example.com",
          created_at: Time.utc(2024, 4, 9)
        )
        reserved_length = "_github-challenge-#{@txt_env_modifier}-ent.github".length

        truncated_slug = business.slug[0, (VerifiableDomain::MAX_TXT_RECORD_LENGTH - reserved_length)]
        assert_equal "_github-challenge-#{@txt_env_modifier}#{truncated_slug}-ent.github", domain.dns_txt_key_copy_challenge
        assert VerifiableDomain::MAX_TXT_RECORD_LENGTH >= domain.dns_txt_key_copy_challenge.length
      end

      test "adapts to domains with subdomains to return record that is 64 characters or less for new TXT record format" do
        business = create(:business, slug: "this-is-quite-an-exceptionally-and-truly-long-business-slug")
        domain = create(
          :verifiable_domain,
          owner: business,
          domain: "github.example.com",
          created_at: Time.utc(2024, 4, 11)
        )
        available_owner_param_length = VerifiableDomain::MAX_TXT_RECORD_LENGTH - "_gh-#{@txt_env_modifier}e.github".length

        truncated_slug = business.slug[0, available_owner_param_length]
        assert_predicate domain, :use_new_txt_record_format?
        assert_equal "_gh-#{@txt_env_modifier}#{truncated_slug}-e.github", domain.dns_txt_key_copy_challenge
        assert domain.dns_txt_key_copy_challenge.length <= 64
      end
    end
  end

  context "#host_name_found?" do
    test "returns false when no TXT record exists with expected host name" do
      mock_dns_setup
      Resolv::DNS.any_instance.stubs(:getresources).with(
        @domain.dns_host_name, Resolv::DNS::Resource::IN::TXT,
      ).returns([])

      refute @domain.async_host_name_found?.sync
      refute @domain.host_name_found?
    end

    test "returns true when a TXT record exists with the expected host name" do
      mock_dns_setup
      mock_dns_verification

      assert @domain.async_host_name_found?.sync
      assert @domain.host_name_found?
    end

    test "returns false when the DNS query attempt times out" do
      mock_dns_setup
      @domain.stubs(:async_dns_records).raises(Resolv::ResolvTimeout)

      refute @domain.async_host_name_found?.sync
      refute @domain.host_name_found?
    end

    test "returns false when the DNS query attempt fails" do
      mock_dns_setup
      @domain.stubs(:async_dns_records).raises(Resolv::ResolvError)

      refute @domain.async_host_name_found?.sync
      refute @domain.host_name_found?
    end
  end

  context "#verification_token_found?" do
    test "returns false when a TXT record is found with the expected host name but the wrong verification token" do
      mock_dns_setup

      record = mock("record")
      record.stubs(:strings).returns(["not a verification token"])
      Resolv::DNS.any_instance.stubs(:getresources).with(
        @domain.dns_host_name, Resolv::DNS::Resource::IN::TXT,
      ).returns([record])

      refute @domain.async_verification_token_found?.sync
      refute @domain.verification_token_found?
    end

    test "returns true when a TXT record is found with the expected host name and verification token" do
      mock_dns_setup
      mock_dns_verification

      assert @domain.async_verification_token_found?.sync
      assert @domain.verification_token_found?
    end

    test "returns false when the DNS query attempt times out" do
      mock_dns_setup
      @domain.stubs(:async_dns_records).raises(Resolv::ResolvTimeout)

      refute @domain.async_verification_token_found?.sync
      refute @domain.verification_token_found?
    end

    test "returns false when the DNS query attempt fails" do
      mock_dns_setup
      @domain.stubs(:async_dns_records).raises(Resolv::ResolvError)

      refute @domain.async_verification_token_found?.sync
      refute @domain.verification_token_found?
    end
  end

  context "#async_dns_records" do
    test "does not peform multiple DNS queries" do
      mock_dns_setup
      Resolv::DNS.any_instance.expects(:getresources).once.with(
        @domain.dns_host_name, Resolv::DNS::Resource::IN::TXT,
      ).returns([])

      2.times { @domain.send(:async_dns_records).sync }
    end

    test "does not perform multiple DNS queries for #host_name_found? and #verification_token_found? for same domain" do
      mock_dns_setup
      Resolv::DNS.any_instance.expects(:getresources).once.with(
        @domain.dns_host_name, Resolv::DNS::Resource::IN::TXT,
      ).returns([])

      @domain.async_host_name_found?.sync
      @domain.async_verification_token_found?.sync
    end
  end

  context "#generate_verification_token" do
    test "generates a new token when there isn't one present" do
      domain = create(:verifiable_domain, owner: @organization, verified: true)
      domain.unverify(actor: @organization_admin) # this will remove the current verification token
      assert domain.verification_token.blank?

      assert domain.generate_verification_token
      domain.reload
      assert domain.verification_token.present?
    end

    test "does not generate a new token when a verification token is already present" do
      domain = create(:verifiable_domain, owner: @organization)
      assert domain.verification_token.present?
      old_token = domain.verification_token

      refute domain.generate_verification_token
      domain.reload
      assert_equal domain.verification_token, old_token
      assert_equal domain.errors.full_messages, ["Verification token is already present."]
    end

    test "does not generate a new token when the domain is already verified" do
      domain = create(:verifiable_domain, owner: @organization)
      old_token = domain.verification_token
      domain.update_attribute(:verified, true)

      refute domain.generate_verification_token
      domain.reload

      assert_equal domain.verification_token, old_token
      assert_equal domain.errors.full_messages, ["Domain is already verified."]
    end
  end

  context "#set_token_expiration_time" do
    test "returns array containing error when the domain has no verification token" do
      domain = create(:verifiable_domain, owner: @organization, verified: true)

      assert_equal \
        ["No verification code was found for this domain"],
        domain.set_token_expiration_time(1.week.from_now.strftime("%Y-%m-%d"), actor: @site_admin)
      assert_nil domain.verification_token
    end

    test "returns array containing error when expires at value does not represent a valid date" do
      domain = create(:verifiable_domain, owner: @organization)
      token = domain.verification_token.dup

      assert_equal \
        ["Verification code expiry time must be a valid date in the future"],
        domain.set_token_expiration_time("whatever", actor: @site_admin)
      assert_equal token, domain.verification_token
    end

    test "returns array containing error when expires at value represents a valid date in the past" do
      expires_at = T.cast(Time.now - 2.weeks, Time)
      domain = create(:verifiable_domain, owner: @organization)
      token = domain.verification_token.dup

      assert_equal \
        ["Verification code expiry time must be a valid date in the future"],
        domain.set_token_expiration_time(expires_at.strftime("%Y-%m-%d"), actor: @site_admin)
      assert_equal token, domain.verification_token
    end

    test "returns empty array when expires at value represents a valid date in the future" do
      expires_at = Time.now + 2.weeks
      domain = create(:verifiable_domain, owner: @organization)
      token = domain.verification_token.dup

      assert_empty domain.set_token_expiration_time(expires_at.strftime("%Y-%m-%d"), actor: @site_admin)
      assert_equal \
        expires_at.strftime("%Y-%m-%d"),
        domain.async_token_expiration_time.sync.strftime("%Y-%m-%d")
      assert_equal token, domain.verification_token
    end
  end

  context "#ensure_domain_not_required_for_policy" do
    test "domain cannot be destroyed if it is the last verified domain and notification restrictions are enabled" do
      domain = create(:verifiable_domain, owner: @organization)
      assert domain.update(verified: true)
      other_domain = create(:verifiable_domain, owner: @organization)

      assert_equal 1, @organization.verifiable_domains.verified.count
      assert @organization.enable_notification_restrictions(actor: @organization.admin)
      assert @organization.restrict_notifications_to_verified_domains?
      refute domain.destroy
      assert_equal ["Domain is required to enforce an organization policy and cannot be deleted"], domain.errors.full_messages
    end
  end

  context "#async_required_for_policy_enforcement?" do
    test "true if notification delivery restriction is enabled and domain is only one verified domain" do
      domain = create(:verifiable_domain, owner: @organization, verified: true)
      other_domain = create(:verifiable_domain, owner: @organization)

      assert_equal 1, @organization.verifiable_domains.verified.count
      assert_equal 0, @organization.verifiable_domains.approved.count
      assert @organization.enable_notification_restrictions(actor: @organization.admin)
      assert @organization.restrict_notifications_to_verified_domains?
      assert domain.async_required_for_policy_enforcement?.sync
      assert domain.required_for_policy_enforcement?
    end

    test "true if notification delivery restriction is enabled and domain is only one approved domain" do
      domain = create(:verifiable_domain, owner: @organization, approved: true)
      other_domain = create(:verifiable_domain, owner: @organization)

      assert_equal 0, @organization.verifiable_domains.verified.count
      assert_equal 1, @organization.verifiable_domains.approved.count
      assert @organization.enable_notification_restrictions(actor: @organization.admin)
      assert @organization.restrict_notifications_to_verified_domains?
      assert domain.async_required_for_policy_enforcement?.sync
      assert domain.required_for_policy_enforcement?
    end

    test "false if notification delivery restriction is not enabled" do
      domain = create(:verifiable_domain, owner: @organization, verified: true)
      other_domain = create(:verifiable_domain, owner: @organization)

      assert_equal 1, @organization.verifiable_domains.verified.count
      refute @organization.restrict_notifications_to_verified_domains?
      refute domain.async_required_for_policy_enforcement?.sync
      refute domain.required_for_policy_enforcement?
    end

    test "false if there are multiple verified or approved domains" do
      domain = create(:verifiable_domain, owner: @organization, verified: true)
      other_domain = create(:verifiable_domain, owner: @organization, approved: true)

      assert_equal 1, @organization.verifiable_domains.verified.count
      assert_equal 1, @organization.verifiable_domains.approved.count
      assert @organization.enable_notification_restrictions(actor: @organization.admin)
      assert @organization.restrict_notifications_to_verified_domains?
      refute domain.async_required_for_policy_enforcement?.sync
      refute domain.required_for_policy_enforcement?
    end
  end

  context "#maybe_required_for_org_policy_enforcement?" do
    test "false if domain is not verified or approved" do
      refute @business_domain.eligible_for_emails?
      assert @business_domain.owner.is_a?(Business)
      refute @business_domain.owner.reload.restrict_notifications_to_verified_domains?
      refute_empty Configuration::Entry.where(name: "restrict_notification_delivery",
                                              value: "true",
                                              target_id: @business.organization_ids,
                                              target_type: "User")

      refute @business_domain.maybe_required_for_org_policy_enforcement?
    end

    test "false if domain is verified, but owner is an Organization" do
      assert @domain.update(verified: true)

      assert @domain.eligible_for_emails?
      refute @domain.owner.is_a?(Business)
      assert_equal 1, @domain.owner.email_eligible_domains.count
      refute @domain.owner.reload.restrict_notifications_to_verified_domains?

      refute @domain.maybe_required_for_org_policy_enforcement?
    end

    test "false if domain is approved, but owner is an Organization" do
      assert @domain.update(approved: true)

      assert @domain.eligible_for_emails?
      refute @domain.owner.is_a?(Business)
      assert_equal 1, @domain.owner.email_eligible_domains.count
      refute @domain.owner.reload.restrict_notifications_to_verified_domains?
      refute_empty Configuration::Entry.where(name: "restrict_notification_delivery",
                                              value: "true",
                                              target_id: @business.organization_ids,
                                              target_type: "User")

      refute @domain.maybe_required_for_org_policy_enforcement?
    end

    test "false if business-owned domain is verified, but is not the last one" do
      @business_domain.update(verified: true)
      create(:verifiable_domain, owner: @business, verified: true)

      assert @business_domain.eligible_for_emails?
      assert @business_domain.owner.is_a?(Business)
      refute_equal 1, @business_domain.owner.email_eligible_domains.count
      refute @business_domain.owner.reload.restrict_notifications_to_verified_domains?
      refute_empty Configuration::Entry.where(name: "restrict_notification_delivery",
                                              value: "true",
                                              target_id: @business.organization_ids,
                                              target_type: "User")

      refute @business_domain.maybe_required_for_org_policy_enforcement?
    end

    test "false if business-owned domain is verified, and we have another domain which is approved" do
      @business_domain.update(verified: true)
      create(:verifiable_domain, owner: @business, approved: true)

      assert @business_domain.eligible_for_emails?
      assert @business_domain.owner.is_a?(Business)
      refute_equal 1, @business_domain.owner.email_eligible_domains.count
      refute @business_domain.owner.reload.restrict_notifications_to_verified_domains?

      refute @business_domain.maybe_required_for_org_policy_enforcement?
    end

    test "returns false for the last verified business domain for a business without an approved domain if notification restrictions are enabled" do
      @business_domain.update(verified: true)
      @business.enable_notification_restrictions(actor: @business.owners.first)

      assert @business_domain.eligible_for_emails?
      assert @business_domain.owner.is_a?(Business)
      assert_equal 1, @business_domain.owner.email_eligible_domains.count
      assert @business_domain.owner.reload.restrict_notifications_to_verified_domains?
      refute_empty Configuration::Entry.where(name: "restrict_notification_delivery",
                                              value: "true",
                                              target_id: @business.organization_ids,
                                              target_type: "User")

      refute @business_domain.maybe_required_for_org_policy_enforcement?
    end

    test "returns false for the last approved business domain for a business without a verified domain if notification restrictions are enabled" do
      @business_domain.update(approved: true)
      @business.enable_notification_restrictions(actor: @business.owners.first)

      assert @business_domain.eligible_for_emails?
      assert @business_domain.owner.is_a?(Business)
      assert_equal 1, @business_domain.owner.email_eligible_domains.count
      assert @business_domain.owner.reload.restrict_notifications_to_verified_domains?
      refute_empty Configuration::Entry.where(name: "restrict_notification_delivery",
                                              value: "true",
                                              target_id: @business.organization_ids,
                                              target_type: "User")

      refute @business_domain.maybe_required_for_org_policy_enforcement?
    end

    test "returns false for last business verified domain for a business without an approved domain, restrictions are disabled, but no orgs have enabled restrictions" do
      @business_domain.update(verified: true)
      @org.disable_notification_restrictions(actor: @org.admin)

      assert @business_domain.eligible_for_emails?
      assert @business_domain.owner.is_a?(Business)
      assert_equal 1, @business_domain.owner.email_eligible_domains.count
      assert_empty Configuration::Entry.where(name: "restrict_notification_delivery",
                                              value: "true",
                                              target_id: @business.organization_ids,
                                              target_type: "User")

      refute @business_domain.maybe_required_for_org_policy_enforcement?
    end

    test "returns false for last business approved domain for a business without a verified domain, restrictions are disabled, but no orgs have enabled restrictions" do
      @business_domain.update(approved: true)
      @org.disable_notification_restrictions(actor: @org.admin)

      assert @business_domain.eligible_for_emails?
      assert @business_domain.owner.is_a?(Business)
      assert_equal 1, @business_domain.owner.email_eligible_domains.count
      assert_empty Configuration::Entry.where(name: "restrict_notification_delivery",
                                              value: "true",
                                              target_id: @business.organization_ids,
                                              target_type: "User")

      refute @business_domain.maybe_required_for_org_policy_enforcement?
    end

    test "returns true for last business verified domain for a business without an approved domain, restrictions are disabled, an org has enabled restrictions" do
      @business_domain.update(verified: true)
      @org.reload.enable_notification_restrictions(actor: @org.admin)

      assert @business_domain.eligible_for_emails?
      assert @business_domain.owner.is_a?(Business)
      assert_equal 1, @business_domain.owner.email_eligible_domains.count
      refute_empty Configuration::Entry.where(name: "restrict_notification_delivery",
                                              value: "true",
                                              target_id: @business.organization_ids,
                                              target_type: "User")

      assert @business_domain.maybe_required_for_org_policy_enforcement?
    end

    test "returns true for last business approved domain for a business without a verified domain, restrictions are disabled, an org has enabled restrictions" do
      @business_domain.update(approved: true)
      @org.reload.enable_notification_restrictions(actor: @org.admin)

      assert @business_domain.eligible_for_emails?
      assert @business_domain.owner.is_a?(Business)
      assert_equal 1, @business_domain.owner.email_eligible_domains.count
      refute_empty Configuration::Entry.where(name: "restrict_notification_delivery",
                                              value: "true",
                                              target_id: @business.organization_ids,
                                              target_type: "User")

      assert @business_domain.maybe_required_for_org_policy_enforcement?
    end
  end

  context "#disable_dependent_policies" do
    test "disables notification restriction if enabled and domain is a verified domain" do
      domain = create(:verifiable_domain, owner: @organization, verified: true)
      assert @organization.enable_notification_restrictions(actor: @organization.admin)
      assert @organization.restrict_notifications_to_verified_domains?
      assert domain.required_for_policy_enforcement?

      domain.disable_dependent_policies(actor: @organization.admin)
      refute @organization.reload.restrict_notifications_to_verified_domains?
      refute domain.required_for_policy_enforcement?
    end

    test "disables notification restriction if enabled and domain is an approved domain" do
      domain = create(:verifiable_domain, owner: @organization, approved: true)
      assert @organization.enable_notification_restrictions(actor: @organization.admin)
      assert @organization.restrict_notifications_to_verified_domains?
      assert domain.required_for_policy_enforcement?

      domain.disable_dependent_policies(actor: @organization.admin)
      refute @organization.reload.restrict_notifications_to_verified_domains?
      refute domain.required_for_policy_enforcement?
    end

    test "doesn't make any changes if notification restrictions not enabled and domain is a verified domain" do
      domain = create(:verifiable_domain, owner: @organization, verified: true)
      refute @organization.restrict_notifications_to_verified_domains?
      refute domain.required_for_policy_enforcement?

      domain.disable_dependent_policies(actor: @organization.admin)
      refute @organization.reload.restrict_notifications_to_verified_domains?
      refute domain.required_for_policy_enforcement?
    end

    test "doesn't make any changes if notification restrictions not enabled and domain is an approved domain" do
      domain = create(:verifiable_domain, owner: @organization, approved: true)
      refute @organization.restrict_notifications_to_verified_domains?
      refute domain.required_for_policy_enforcement?

      domain.disable_dependent_policies(actor: @organization.admin)
      refute @organization.reload.restrict_notifications_to_verified_domains?
      refute domain.required_for_policy_enforcement?
    end
  end

  context "#owner" do
    test "can be an organization" do
      verifiable_domain = create(:verifiable_domain, owner: @organization)
      assert verifiable_domain.valid?
      domain = VerifiableDomain.find(verifiable_domain.id)
      refute_nil domain
      assert_equal "User", domain.owner_type
      assert_equal @organization.id, domain.owner_id
    end

    test "validates that the owner cannot be a User" do
      verifiable_domain = VerifiableDomain.new(
        domain: "https://www.bad-owner.com",
        owner: create(:user)
      )

      assert VerifiableDomain::VALID_OWNER_TYPES.include?(verifiable_domain.owner_type)
      refute verifiable_domain.valid?
      assert_equal ["must be an Organization when owner_type is User"],
                   verifiable_domain.errors[:owner]
    end

    test "validates that the owner cannot be a Bot" do
      verifiable_domain = VerifiableDomain.new(
        domain: "https://www.bad-owner.com",
        owner: create(:bot)
      )

      assert VerifiableDomain::VALID_OWNER_TYPES.include?(verifiable_domain.owner_type)
      refute verifiable_domain.valid?
      assert_equal ["must be an Organization when owner_type is User"],
                   verifiable_domain.errors[:owner]
    end

    test "can be a business" do
      enterprise_domain = create(:verifiable_domain, owner: @business)
      assert enterprise_domain.valid?
      domain = VerifiableDomain.find(enterprise_domain.id)
      refute_nil domain
      assert_equal "Business", domain.owner_type
      assert_equal @business.id, domain.owner_id
    end

    test "owner_type can only be User or Business" do
      verifiable_domain = VerifiableDomain.new(
        domain: "https://www.bad-owner.com",
        owner: create(:repository, :minimal)
      )

      refute VerifiableDomain::VALID_OWNER_TYPES.include?(verifiable_domain.owner_type)
      refute verifiable_domain.valid?
      assert_equal ["is not included in the list"], verifiable_domain.errors[:owner_type]
    end
  end

  context "#domain_audit_log_query" do
    test "returns correct event prefix for Organization-owned domain" do
      expected_query = "(data.organization_domain_id:#{@domain.id} OR data.verifiable_domain_id:#{@domain.id}) AND (action:organization_domain.* OR action:staff.*verify_domain)"
      assert_equal expected_query, @domain.domain_audit_log_query
    end

    test "returns correct event prefix for Business-owned domain" do
      expected_query = "data.verifiable_domain_id:#{@business_domain.id} AND (action:enterprise_domain.* OR action:staff.*verify_domain)"
      assert_equal expected_query, @business_domain.domain_audit_log_query
    end
  end

  context "#usable_for" do
    test "returns entries for Organization" do
      if TestEnv.test_in_multitenancy_mode?
        assert_same_elements [@domain, @business_domain], VerifiableDomain.usable_for(@organization).all
      else
        assert_equal [@domain], VerifiableDomain.usable_for(@organization).all
      end
    end

    test "returns entries for Organization and its parent Business" do
      business_org = create(:organization)
      @business.add_organization(business_org)
      business_org.reload
      business_domain = create(:verifiable_domain, owner: @business)
      organization_domain = create(:verifiable_domain, owner: business_org)
      assert_same_elements [business_domain, organization_domain, @business_domain],
        VerifiableDomain.usable_for(business_org).all
    end

    test "returns entries for Business" do
      business_domain = create(:verifiable_domain, owner: @business)
      assert_same_elements [business_domain, @business_domain], VerifiableDomain.usable_for(@business).all
    end
  end

  context "#organizations_for_profile_domain" do
    context "when owner is an organization" do
      test "returns the owner if its profile domain matches" do
        email_domain = "http://email.com"
        email_domain = create(:verifiable_domain, domain: email_domain, owner: @organization)
        @organization.create_profile(blog: @domain_name, email: "user@email.com")
        assert_equal [@organization], @domain.organizations_for_profile_domain
        assert_equal [@organization], email_domain.organizations_for_profile_domain
      end

      test "returns empty array if neither profile domain matches" do
        @organization.create_profile(blog: "blog.com", email: "user@email.com")
        assert_empty @domain.organizations_for_profile_domain
      end

      test "does not return another organization within a parent business" do
        org = create(:organization, :org_with_sanctioned_profile_blog)
        @business.add_organization org
        @business.add_organization @organization
        org_domain = create(:verifiable_domain, owner: @organization, domain: org.profile_blog)
        assert_empty org_domain.organizations_for_profile_domain
      end
    end

    context "when owner is a Business" do
      test "returns all the organizations that have at least one profile domain that matches" do
        org_with_email = create(:organization)
        org_with_email.create_profile(email: "admin@#{@business_domain_name}")
        org_with_blog = create(:organization)
        org_with_blog.create_profile(blog: "http://#{@business_domain_name}/blog.html")
        org_with_profile_domains = create(:organization)
        org_with_profile_domains.create_profile(email: "email.com", blog: "blog.com")
        org_no_profile = create(:organization)

        [org_with_email, org_with_blog, org_with_profile_domains, org_no_profile].each do |org|
          @business.add_organization(org)
        end

        assert_same_elements [org_with_email, org_with_blog],
                             @business_domain.organizations_for_profile_domain
      end

      test "returns an empty array if no member organizations match" do
        @business.add_organization(@organization)
        @business.add_organization(create(:organization))
        domain = create(:verifiable_domain, owner: @business, domain: "cycle.com")
        assert_empty domain.organizations_for_profile_domain
      end
    end
  end

  context "#eligible_for_emails?" do
    test "false by default" do
      refute create(:verifiable_domain).eligible_for_emails?
    end

    test "true if domain is verified" do
      assert create(:verifiable_domain, verified: true).eligible_for_emails?
    end

    test "true if domain is approved" do
      assert create(:verifiable_domain, approved: true).eligible_for_emails?
    end
  end

  context "self.approved_domain_emails_visible_to_admins?" do
    if GitHub.enterprise?
      test "returns true on GHES" do
        assert VerifiableDomain.approved_domain_emails_visible_to_admins?
      end
    else
      test "returns false on dotcom" do
        refute VerifiableDomain.approved_domain_emails_visible_to_admins?
      end
    end
  end

  context "instrumentation" do
    test "when owner is an org" do
      events = subscribe "organization_domain.create"
      domain = create(:verifiable_domain, owner: @org, verified: true)

      expected_payload = {
        verifiable_domain_id: domain.id,
        owner: @org.display_login,
        owner_id: @org.id,
        owner_type: "User",
        domain_name: domain.domain,
        org: @org.display_login,
        org_id: @org.id,
        business: @org.business.slug,
        business_id: @org.business.id,
      }

      assert event = events.pop, "a organization_domain.create event was expected"
      assert_equal "organization_domain.create", event.name
      assert_subset_hash expected_payload, event.payload
    end

    test "when owner is an business" do
      events = subscribe "enterprise_domain.create"
      domain = create :verifiable_domain, owner: @business

      expected_payload = {
        verifiable_domain_id: domain.id,
        owner: @business.slug,
        owner_id: @business.id,
        owner_type: "Business",
        domain_name: domain.domain,
        business: @business.slug,
        business_id: @business.id,
      }

      assert event = events.pop, "a enterprise_domain.create event was expected"
      assert_equal "enterprise_domain.create", event.name
      assert_subset_hash expected_payload, event.payload
    end
  end

  private

  def mock_dns_setup(domain_name: @domain_name)
    Resolv::DNS.any_instance.stubs(:getresources).with(
      domain_name, Resolv::DNS::Resource::IN::NS
    ).returns([])
  end

  def mock_dns_verification(
    verification_token: @domain.verification_token,
    dns_record_url: @domain.dns_host_name
  )
    txt_record = mock("txt_record")
    txt_record.stubs(:strings).returns([verification_token])
    txt_record.stubs(:is_a?).returns(Resolv::DNS::Resource::IN::TXT)
    Resolv::DNS.any_instance.stubs(:getresources).with(
      dns_record_url,
      Resolv::DNS::Resource::IN::TXT,
    ).returns([txt_record])
  end
end
