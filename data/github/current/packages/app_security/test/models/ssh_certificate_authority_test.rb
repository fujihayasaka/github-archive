# typed: true
# frozen_string_literal: true

require "test_helper"

class SshCertificateAuthorityTest < GitHub::TestCase
  fixtures do
    @priv = SSHData::PrivateKey::RSA.generate(2048).freeze
    @ca = create(:ssh_certificate_authority, private_key: @priv)
    @user = create(:user)
  end

  context "usable_for" do
    test "user owned repo" do
      repo = create(:repository, owner: create(:user))
      assert_predicate SshCertificateAuthority.usable_for(repo), :none?
    end

    test "org owned repo" do
      ca = create(:ssh_certificate_authority, :org)
      repo = create(:repository, owner: ca.owner)
      assert_equal SshCertificateAuthority.usable_for(repo).all, [ca]
      assert_equal SshCertificateAuthority.usable_for(ca.owner).all, [ca]
    end

    test "business owned repo" do
      bom = create(:business_organization_membership, organization: create(:business_plus_org))
      org = bom.organization.reload
      business = bom.business.reload

      oca = create(:ssh_certificate_authority, owner: org)
      bca = create(:ssh_certificate_authority, owner: business)
      repo = create(:repository, owner: org)

      assert_equal 2, SshCertificateAuthority.usable_for(repo).count
      assert_includes SshCertificateAuthority.usable_for(repo), oca
      assert_includes SshCertificateAuthority.usable_for(repo), bca

      assert_equal 2, SshCertificateAuthority.usable_for(org).count
      assert_includes SshCertificateAuthority.usable_for(org), oca
      assert_includes SshCertificateAuthority.usable_for(org), bca

      assert_equal SshCertificateAuthority.usable_for(business).all, [bca]
    end
  end

  context "fips mode" do
    test "allows ed25519 keys not in FIPS mode" do
      GitHub.stubs(:fips_mode?).returns(false)
      assert_predicate build(:ssh_certificate_authority, :ed25519), :valid?
    end

    test "blocks ed25519 keys in FIPS mode" do
      GitHub.stubs(:fips_mode?).returns(true)
      refute_predicate build(:ssh_certificate_authority, :ed25519), :valid?
    end
  end

  context "#depended_on_for_cert_requirement?" do
    test "org has cert requirement, org has one ca" do
      ca = create(:ssh_certificate_authority, :org)
      ca.owner.enable_ssh_certificate_requirement(ca.owner)

      ca.owner.reload

      assert_predicate ca.owner, :ssh_certificate_requirement_enabled?
      assert_predicate ca, :depended_on_for_cert_requirement?
    end

    test "org doesn't have cert requirement, org has one ca" do
      ca = create(:ssh_certificate_authority, :org)
      refute_predicate ca, :depended_on_for_cert_requirement?
    end

    test "org has cert requirement, org has two cas" do
      ca1 = create(:ssh_certificate_authority, :org)
      ca2 = create(:ssh_certificate_authority, owner: ca1.owner)
      ca1.owner.enable_ssh_certificate_requirement(ca1.owner)

      ca1.owner.reload

      assert_predicate ca1.owner, :ssh_certificate_requirement_enabled?
      refute_predicate ca1, :depended_on_for_cert_requirement?
      refute_predicate ca2, :depended_on_for_cert_requirement?
    end

    test "business has cert requirement, business has one ca" do
      ca = create(:ssh_certificate_authority, :business)
      ca.owner.enable_ssh_certificate_requirement(@user)

      ca.owner.reload

      assert_predicate ca.owner, :ssh_certificate_requirement_enabled?
      assert_predicate ca, :depended_on_for_cert_requirement?
    end

    test "business doesn't have cert requirement, business has one ca" do
      ca = create(:ssh_certificate_authority, :business)
      refute_predicate ca, :depended_on_for_cert_requirement?
    end

    test "business has cert requirement, business has two ca" do
      ca1 = create(:ssh_certificate_authority, :business)
      ca2 = create(:ssh_certificate_authority, owner: ca1.owner)
      ca1.owner.enable_ssh_certificate_requirement(@user)

      ca1.owner.reload

      assert_predicate ca1.owner, :ssh_certificate_requirement_enabled?
      refute_predicate ca1, :depended_on_for_cert_requirement?
      refute_predicate ca2, :depended_on_for_cert_requirement?
    end

    test "org has cert requirement, business has one ca" do
      org = create(:business_plus_org)
      business = create(:business_organization_membership, organization: org).business
      ca = create(:ssh_certificate_authority, owner: business)
      org.enable_ssh_certificate_requirement(org.owner)

      business.reload
      org.reload

      assert_predicate org, :ssh_certificate_requirement_enabled?
      assert_predicate ca, :depended_on_for_cert_requirement?
    end

    test "org doesn't have cert requirement, business has one ca" do
      org = create(:business_plus_org)
      business = create(:business_organization_membership, organization: org).business
      ca = create(:ssh_certificate_authority, owner: business)

      business.reload
      org.reload

      refute_predicate ca, :depended_on_for_cert_requirement?
    end

    test "org has cert requirement, org has one ca, business has one ca" do
      org = create(:business_plus_org)
      business = create(:business_organization_membership, organization: org).business
      business_ca = create(:ssh_certificate_authority, owner: business)
      org.enable_ssh_certificate_requirement(org.owner)
      org_ca = create(:ssh_certificate_authority, owner: org)

      business.reload
      org.reload

      assert_predicate org, :ssh_certificate_requirement_enabled?
      refute_predicate business_ca, :depended_on_for_cert_requirement?
      refute_predicate org_ca, :depended_on_for_cert_requirement?
    end
  end

  [
    [:rsa,     SSHData::PrivateKey::RSA.generate(2048)],
    [:ecdsa,   SSHData::PrivateKey::ECDSA.generate("nistp256")],
    [:ed25519, SSHData::PrivateKey::ED25519.generate],
  ].each do |ca_key_type, ca_priv|
    context "#{ca_key_type} CA" do
      test "can be created" do
        assert_predicate create(:ssh_certificate_authority, ca_key_type), :valid?
      end

      test "#base64_fingerprint works" do
        ca = create(:ssh_certificate_authority, private_key: ca_priv)
        assert_equal ca_priv.public_key.fingerprint, ca.base64_fingerprint
      end
    end
  end

  test "cannot use DSA keys" do
    ca = build(:ssh_certificate_authority, :dsa)
    refute_predicate ca, :valid?
    refute_empty ca.errors[:openssh_public_key]
  end

  test "cannot use small RSA keys" do
    ca = build(:ssh_certificate_authority,
      openssh_public_key: SSHData::PrivateKey::RSA.generate(1024,
        unsafe_allow_small_key: true,
      ).public_key.openssh,
    )

    refute_predicate ca, :valid?
    refute_empty ca.errors[:openssh_public_key]
  end

  test "cannot use known compromised keys" do
    ca = build(:ssh_certificate_authority,
      openssh_public_key: File.read(Rails.root.join("test/fixtures/keys/compromised-rsa.pub")),
    )

    refute_predicate ca, :valid?
    refute_empty ca.errors[:openssh_public_key]
  end

  test "cannot use easily factorable RSA keys" do
    ca = build(:ssh_certificate_authority,
      openssh_public_key: File.read(Rails.root.join("test/fixtures/keys/factorable_rsa.pub")),
    )

    refute_predicate ca, :valid?
    refute_empty ca.errors[:openssh_public_key]
  end

  test "cannot create with invalid key" do
    ca = build(:ssh_certificate_authority, openssh_public_key: "bad")
    refute_predicate ca, :valid?
    refute_empty ca.errors[:openssh_public_key]
  end

  test "cannot be created with duplicate key" do
    ca = build(:ssh_certificate_authority,
      openssh_public_key: create(:ssh_certificate_authority).openssh_public_key,
    )
    refute_predicate ca, :valid?
    refute_empty ca.errors[:openssh_public_key]
    assert_empty ca.errors[:fingerprint]
  end

  test "cannot be created without a business plus plan" do
    ca = build(:ssh_certificate_authority,
      owner: create(:organization, plan: GitHub::Plan::BUSINESS),
    )

    refute_predicate ca, :valid?
    refute_empty ca.errors[:owner]
  end

  [:org, :business, :business_org].each do |owner_type|
    test "can be created with #{owner_type} owner" do
      assert_predicate create(:ssh_certificate_authority, owner_type), :valid?
    end

    test "#owned_by? works with #{owner_type} owner" do
      ca = create(:ssh_certificate_authority, owner_type)
      assert ca.owned_by?(ca.owner)
    end

    test "#{owner_type}<->ca relation works" do
      ca = create(:ssh_certificate_authority, owner_type)
      assert_equal ca, ca.owner.ssh_certificate_authorities.first
    end

    test "#{owner_type} is not deleted along with ca (sanity check)" do
      ca = create(:ssh_certificate_authority, owner_type)
      ca.destroy
      ca.owner.reload
    end

    test "create is instrumented for #{owner_type} ca" do
      events = subscribe("ssh_certificate_authority.create")
      ca = create(:ssh_certificate_authority, owner_type)

      expected_payload = {
        :ssh_certificate_authority_id        => ca.id,
        :openssh_public_key                  => ca.openssh_public_key,
        :fingerprint                         => ca.base64_fingerprint,
        ca.owner.event_prefix                => ca.owner.to_s,
        "#{ca.owner.event_prefix}_id".intern => ca.owner.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "ssh_certificate_authority.create", event.name
      assert_equal expected_payload, event.payload
    end

    test "destroy is instrumented for #{owner_type} ca" do
      ca = create(:ssh_certificate_authority, owner_type)
      events = subscribe("ssh_certificate_authority.destroy")
      ca.destroy

      expected_payload = {
        :ssh_certificate_authority_id        => ca.id,
        :openssh_public_key                  => ca.openssh_public_key,
        :fingerprint                         => ca.base64_fingerprint,
        ca.owner.event_prefix                => ca.owner.to_s,
        "#{ca.owner.event_prefix}_id".intern => ca.owner.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "ssh_certificate_authority.destroy", event.name
      assert_equal expected_payload, event.payload
    end
  end

  test "cannot create with invalid owner type" do
    ca = build(:ssh_certificate_authority, owner: create(:user))
    refute_predicate ca, :valid?
    refute_empty ca.errors[:owner]
  end

  test "does not error with malformed SSH key" do
    ca_key = "ssh-rsa AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    assert_raises ActiveRecord::RecordInvalid do
      create(:ssh_certificate_authority, openssh_public_key: ca_key)
    end
  end

  context "proxima ssh ca keys", skip_enterprise: true do
    test "may be reused across tenants" do
      ssh_pub_key = SSHData::PrivateKey::RSA.generate(2048).public_key.openssh

      owner1 = create :emu
      business1 = owner1.enterprise_managed_business
      on_multi_tenant_enterprise(tenant: business1) do
        @ca1 = build(:ssh_certificate_authority, owner: business1, openssh_public_key: ssh_pub_key)
        assert @ca1.save!
      end

      owner2 = create :emu
      business2 = owner2.enterprise_managed_business
      on_multi_tenant_enterprise(tenant: business2) do
        @ca2 = build(:ssh_certificate_authority, owner: business2, openssh_public_key: ssh_pub_key)
        assert @ca2.save!
      end

      assert_equal @ca1.base64_fingerprint, @ca2.base64_fingerprint
      refute_equal @ca1.fingerprint, @ca2.fingerprint
    end

    test "may not be reused in the same tenant" do
      ssh_pub_key = SSHData::PrivateKey::RSA.generate(2048).public_key.openssh

      owner = create :emu
      business = owner.enterprise_managed_business
      on_multi_tenant_enterprise(tenant: business) do
        ca = build(:ssh_certificate_authority,
          owner: business,
          openssh_public_key: create(:ssh_certificate_authority, owner: business).openssh_public_key,
        )
        refute_predicate ca, :valid?
        refute_empty ca.errors[:openssh_public_key]
        assert_empty ca.errors[:fingerprint]
      end

    end

    test "are saved with '_{shortcode}' appended to the fingerprint" do
      owner = create :emu
      business = owner.enterprise_managed_business
      on_multi_tenant_enterprise(tenant: business) do
        ca = create(:ssh_certificate_authority)
        assert_equal ca.fingerprint, Base64.decode64(ca.base64_fingerprint + "_" + business.shortcode)
      end
    end
  end

  context "#max_cert_lifetime" do
    test "always set max cert lifetime by default on proxima" do
      on_multi_tenant_enterprise do
        ca = create(:ssh_certificate_authority, skip_add_default_max_ssh_cert_lifetime: false)
        assert_equal GitAuth::SSHCertificateAuthority::DEFAULT_MAX_SSH_CERT_LIFETIME_IN_HOURS, ca.max_ssh_cert_lifetime_hours
      end
    end

    test "always set max cert lifetime by default on GHES" do
      ca = create(:ssh_certificate_authority, skip_add_default_max_ssh_cert_lifetime: false)
      assert_equal GitAuth::SSHCertificateAuthority::DEFAULT_MAX_SSH_CERT_LIFETIME_IN_HOURS, ca.max_ssh_cert_lifetime_hours
    end if GitHub.enterprise?

    test "only set default max cert lifetime on GHEC after specific date" do
      Timecop.freeze(SshCertificateAuthority::SET_DEFAULT_MAX_SSH_CERT_LIFETIME_AFTER_DATE - 1.second) do
        ca = create(:ssh_certificate_authority, skip_add_default_max_ssh_cert_lifetime: false)
        assert_nil ca.max_ssh_cert_lifetime_hours
      end

      Timecop.freeze(SshCertificateAuthority::SET_DEFAULT_MAX_SSH_CERT_LIFETIME_AFTER_DATE) do
        ca = create(:ssh_certificate_authority, skip_add_default_max_ssh_cert_lifetime: false)
        assert_equal GitAuth::SSHCertificateAuthority::DEFAULT_MAX_SSH_CERT_LIFETIME_IN_HOURS, ca.max_ssh_cert_lifetime_hours
      end
    end unless GitHub.enterprise? || GitHub.multi_tenant_enterprise?
  end
end
