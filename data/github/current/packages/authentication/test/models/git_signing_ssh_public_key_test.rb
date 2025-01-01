# typed: true
# frozen_string_literal: true

require "test_helper"

class GitSigningSshPublicKeyTest < GitHub::TestCase
  include DogstatsTestHelpers

  setup do
    @dsa_key = "ssh-dss AAAAB3NzaC1kc3MAAACBAISD++1zGHsG2Ia1GORcTymxNQpigIHj7XcaG7IHTejkzS+o/e5Y4wsxa7jjoryUrRZvXwLPbHsUsw/KO7DK+fbJjwyrrmXImD6KIJKcOG5viOkqWjP0NdU1W9lMTq8uoNr3PY5V8yWI4a0FSyRWcOAONUrtYh+tKlGaYOBh2VNlAAAAFQDYE4p8NnGbPacqNccjtIqo4DQyTwAAAIAUtOCPmwm8pJ0OZ78EADlcTYr0RHRv8y3mHucoS5DJj8cYajt1Hh9tbYx4d+GilmXYOljnNzI5jiOd7TVK+yrc5odswZkxC/KBRCGEpNCpfEEBH6j6lDgmds4y/GYi8AQ4ERRdqeETijl9UWRPFebPT05h66WMuvYTq0TUNLvvoQAAAIBWXa1ECiCfNh9ZkTYVFkdsVhOxwwfjFBlGvI7m2ol2Kd+eUOiVoz2D9d+Gk7N/vDmwI1N20rrSRRMlJiqHR6h1XKfuTYJRS1sQ6faPMMy3yBS4qHUpW7Qe5rhzIuxlZHGMn5ZiGRezz/msoFlbV8guNltV/lBtTWMu5B5KdcmgyA=="
    @rsa_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDZOPsKCabUz+RnJKMpaVFoXduLNtRHDT65ll+uBvzeBx8xl+Gp588uTs3HtHeJdBSeOZITaOK77XBZlW7TOJYHN0R0KAcK5cPaSf6mAaRDxeCHs9CCfnKlaXROW0n7HYcU52p8nSjDCsYT8N2Da9vIq96LQShji2dDXrj/kaCuHCxpNCmYvzt83GhhpCLeClLO+IS/RF9n7c6jqxwExSNacjXIEPUspk3H1QOzyhD99TeykOTKWpZCAYTFKztnxjEI6oXZd3BBtB0NvSxAiEUg5oluleB0vEDfBknkDphLqmb2+nkjJ8UZt1AhL998rH7CX4sG0O9SgtunrRJJ9BXv"

    fixture_dir = Rails.root.join("test", "fixtures", "keys")
    @test_keys = {
      corrupted: File.read("#{fixture_dir}/corrupted.pub"),
      valid: File.read("#{fixture_dir}/valid.pub"),
      privkey: File.read("#{fixture_dir}/valid"),
      valid_newlines: File.read("#{fixture_dir}/valid_newlines.pub"),
      compromised: File.read("#{fixture_dir}/compromised.pub"),
      rsa_256: File.read("#{fixture_dir}/rsa_256.pub"),
      factorable_rsa: File.read("#{fixture_dir}/factorable_rsa.pub"),
      bad_fingerprint: File.read("#{fixture_dir}/bad_fingerprint.pub"),
    }
  end

  fixtures do
    @mojombo = create(:user, login: "mojombo")
    @repo = create(:repository)

    @repository_network = create(:repository_network)
    @root_repo = @repository_network.root
    @policymaker = @root_repo.owner

    @public_source_repo = create(:public_repository, owner: @policymaker)
    @public_source_repo.update!(network: @repository_network)

    # Public repo in same network but different owner
    @excluded_public_repo = create(:public_repository)
    @excluded_public_repo.update!(network: @repository_network)

    @private_source_repo = create(:private_repository)
    @private_source_repo.update!(network: @repository_network)

    # Private repo in different network but same owner
    @other_repository_network = create(:repository_network)
    @excluded_private_repo = create(:private_repository, owner: @policymaker)
    @excluded_private_repo.update!(network: @other_repository_network)

    @application = create(:oauth_application)
    @authorization = create(:oauth_authorization, application: @application)
  end

  test "must have either user_id set" do
    key = GitSigningSshPublicKey.new key: @rsa_key
    refute key.save
    key.user = @mojombo
    assert key.save

    key.user = nil
    refute key.save
  end

  test "uses the key comment if provided with no title" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: "#@rsa_key jmaddox@iMac.local" })
    assert_equal "jmaddox@iMac.local", public_key.title
  end

  test "keeps the title nil if key comment isn't provided with no title" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
    assert_nil public_key[:title]
  end

  test "fails for title longer than 255 characters" do
    ttl = "a" * 300
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: ttl, key: @rsa_key })
    refute_predicate public_key, :valid?
  end

  test "uses the title" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: "my server key", key: "#@rsa_key jmaddox@iMac.local" })
    assert_equal "my server key", public_key.title
  end

  test "return title as the first 25 chars of the key when title is nil" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
    assert_equal "ssh-rsa AAAAB3NzaC1yc2EAAA", public_key.title
  end

  test "returns title as the actual title when title is NOT nil" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: "my server key", key: @rsa_key })
    assert_equal "my server key", public_key.title
  end

  test "strips SSH: prefixes" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: "SSH:#{@rsa_key}" })
    assert_equal @rsa_key, public_key.key
  end

  test "prints SHA256 prefix for fingerprints" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
    assert_equal "SHA256:hEbBwmrDwB9JZpczmTQnc5wbBeT+Lw+wHFmDMwRiUjI", public_key.fingerprint
  end

  test "fails if the key isn't a key" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: "bad key", key: "Hi there, I'm not a key at all!" })
    refute_predicate public_key, :valid?
  end

  test "fails for ssh-dss keys when deprecate feature is enabled" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: "ssh-dss key", key: @dsa_key })
    refute_predicate public_key, :valid?
    assert_equal public_key.errors[:key], ["is invalid. It must begin with 'ssh-rsa', 'ecdsa-sha2-nistp256', 'ecdsa-sha2-nistp384', 'ecdsa-sha2-nistp521', 'ssh-ed25519', 'sk-ecdsa-sha2-nistp256@openssh.com', 'sk-ssh-ed25519@openssh.com'. Check that you're copying the public half of the key"]
  end

  test "permits sk-ssh-ed25519@openssh.com for repository" do
    public_key = build(:public_key, :sk_ed25519, repository: @repo)
    assert_predicate public_key, :valid?
  end

  test "permits sk-ssh-ed25519@openssh.com for user" do
    public_key = build(:public_key, :sk_ed25519, user: @mojombo)
    assert_predicate public_key, :valid?
  end

  test "catches parse errors when there is bad algorithm names" do
    ill_formed_key = "Ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDZOPsKCabUz+RnJKMpaVFoXduLNtRHDT65ll+uBvzeBx8xl+Gp588uTs3HtHeJdBSeOZITaOK77XBZlW7TOJYHN0R0KAcK5cPaSf6mAaRDxeCHs9CCfnKlaXROW0n7HYcU52p8nSjDCsYT8N2Da9vIq96LQShji2dDXrj/kaCuHCxpNCmYvzt83GhhpCLeClLO+IS/RF9n7c6jqxwExSNacjXIEPUspk3H1QOzyhD99TeykOTKWpZCAYTFKztnxjEI6oXZd3BBtB0NvSxAiEUg5oluleB0vEDfBknkDphLqmb2+nkjJ8UZt1AhL998rH7CX4sG0O9SgtunrRJJ9BXv"
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: "ssh-dss key", key: @ill_formed_key })
    refute_predicate public_key, :valid?
    assert_equal public_key.errors[:key], ["is invalid. You must supply a key in OpenSSH public key format"]
  end

  test "catches parse errors when there is non ascii char in algorithm names" do
    ill_formed_key = "âsh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDZOPsKCabUz+RnJKMpaVFoXduLNtRHDT65ll+uBvzeBx8xl+Gp588uTs3HtHeJdBSeOZITaOK77XBZlW7TOJYHN0R0KAcK5cPaSf6mAaRDxeCHs9CCfnKlaXROW0n7HYcU52p8nSjDCsYT8N2Da9vIq96LQShji2dDXrj/kaCuHCxpNCmYvzt83GhhpCLeClLO+IS/RF9n7c6jqxwExSNacjXIEPUspk3H1QOzyhD99TeykOTKWpZCAYTFKztnxjEI6oXZd3BBtB0NvSxAiEUg5oluleB0vEDfBknkDphLqmb2+nkjJ8UZt1AhL998rH7CX4sG0O9SgtunrRJJ9BXv"
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: "ssh-dss key", key: @ill_formed_key })
    refute_predicate public_key, :valid?
    assert_equal public_key.errors[:key], ["is invalid. You must supply a key in OpenSSH public key format"]
  end

  test "passes if the key is for reals" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: "bad key", key: @test_keys[:valid] })
    assert public_key.valid?
  end

  test "passes if the key contains newlines" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: "bad key", key: @test_keys[:valid_newlines] })
    assert public_key.valid?
  end

  test "fails if the key is a private key" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: "bad key", key: @test_keys[:privkey] })
    refute_predicate public_key, :valid?
  end

  test "fails if the key is a compromised debian key" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: "compromised key", key: @test_keys[:compromised] })
    refute_predicate public_key, :valid?
  end

  test "fails if the key looks legit but is corrupted" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: "bad key", key: @test_keys[:corrupted] })
    refute_predicate public_key, :valid?
  end

  test "fails validation on invalid fingerprint" do
    # This doesn't look like a key at all, so fingerprint validation fails
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: "deadbeef" })
    assert_nil public_key.fingerprint_sha256
    refute_predicate public_key, :valid?

    # bongus second part key can't be enough to fingerprint.
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: "ssh-rsa deadbeef" })
    assert_nil public_key.fingerprint_sha256
    refute_predicate public_key, :valid?
  end

  test "fails validation if under 2048 bits long" do
    short_key = @mojombo.git_signing_ssh_public_keys.build({ title: "weak key", key: @test_keys[:rsa_256] })
    refute_predicate short_key, :valid?
    assert_equal 1, short_key.errors[:key].length
    assert short_key.errors[:key].first.match?(/is too short/)

    long_key = @mojombo.git_signing_ssh_public_keys.build(
      { title: "weak key", key: SSHKey.generate(type: "RSA", bits: 2048).ssh_public_key }
    )
    long_key.validate
    assert_predicate long_key, :valid?
  end

  test "fails validation if factorable" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: "factorable key", key: @test_keys[:factorable_rsa] })
    refute_predicate public_key, :valid?
    assert public_key.errors[:key]
  end

  test "fails validation if infineon vulnerable" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: "factorable key", key: @test_keys[:bad_fingerprint] })
    refute_predicate public_key, :valid?
    assert public_key.errors[:key]
  end

  test "instruments creation" do
    events = subscribe "git_signing_ssh_public_key.create"
    user = create :user, login: "a-user"
    org  = create :organization, login: "an-org", admin: user
    key = create(:git_signing_ssh_public_key, user: @mojombo)

    expected_payload = {
      git_signing_ssh_public_key_id: key.id,
      title: key.title,
      key: key.key,
      fingerprint: key.fingerprint,
      user: key.user.login,
      user_id: key.user_id,
    }

    assert event = events.pop, "an event was expected"
    assert_equal "git_signing_ssh_public_key.create", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments creation with actor context" do
    events = subscribe "git_signing_ssh_public_key.create"
    user = create :user, login: "a-user"

    key = GitHub.context.push(actor: user) do
      create(:git_signing_ssh_public_key, user: @mojombo)
    end

    expected_payload = {
      git_signing_ssh_public_key_id: key.id,
      title: key.title,
      key: key.key,
      fingerprint: key.fingerprint,
      user: key.user.login,
      user_id: key.user_id,
      actor: user.login,
      actor_id: user.id,
    }

    assert event = events.pop, "an event was expected"
    assert_equal "git_signing_ssh_public_key.create", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments deletion for public_key.delete event" do
    key = create(:git_signing_ssh_public_key, user: @mojombo)
    events = subscribe "git_signing_ssh_public_key.delete"

    expected_payload = {
      git_signing_ssh_public_key_id: key.id,
      title: key.title,
      key: key.key,
      fingerprint: key.fingerprint,
      user: key.user.login,
      user_id: key.user_id,
      explanation: :removed_by_user,
      incident: nil,
    }

    key.destroy_with_explanation(:removed_by_user)

    assert event = events.pop, "an event was expected"
    assert_equal "git_signing_ssh_public_key.delete", event.name
    assert_equal expected_payload, event.payload
  end

  test "does not allow duplicate keys" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
    assert public_key.valid?

    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
    refute_predicate public_key, :valid?
    assert_match /already in use/, public_key.errors[:key].first
  end

  test "does not allow a user to create a signing key if another user has a public key with the same fingerprint" do
    other_user = create(:user)
    other_user.public_keys.create!({ title: nil, key: @rsa_key })

    signing_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
    refute_predicate signing_key, :valid?
    assert_match /already in use/, signing_key.errors[:key].first
  end

  test "allows a user to create a signing key if they have a public key with the same fingerprint" do
    @mojombo.public_keys.create!({ title: nil, key: @rsa_key })

    signing_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
    assert signing_key.valid?
  end

  test "a signing key is not valid if it has the same fingerprint as a deploy key" do
    @repo.public_keys.create!({ title: nil, key: @rsa_key })

    signing_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })

    refute_predicate signing_key, :valid?
    assert_match /already in use/, signing_key.errors[:key].first
  end

  test "ignores duplicates of badly formatted keys" do
    bad_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
    bad_key.key = "#@rsa_key my name is <bob@aol.com>\n"
    assert_equal true, bad_key.save(validate: false)

    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
    refute_predicate public_key, :valid?
    assert_match /already in use/, public_key.errors[:key].first
  end

  test "checks uniqueness on save" do
    public_key = @mojombo.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
    public_key.save!
  end

  context "fips mode" do
    test "allows ed25519 keys not in FIPS mode" do
      GitHub.stubs(:fips_mode?).returns(false)
      public_key = @mojombo.git_signing_ssh_public_keys.create(title: "ed25519 key", key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINzroZG/Uhzz7Pwjr8Q2JlqVHcsC1yKdTm8IdQz2zX6j dirkjan@dbussink.archimedes.bussink.me")
      assert_predicate public_key, :valid?
    end

    test "blocks ed25519 keys in FIPS mode" do
      GitHub.stubs(:fips_mode?).returns(true)
      public_key = @mojombo.git_signing_ssh_public_keys.create(title: "ed25519 key", key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINzroZG/Uhzz7Pwjr8Q2JlqVHcsC1yKdTm8IdQz2zX6j dirkjan@dbussink.archimedes.bussink.me")
      refute_predicate public_key, :valid?
      assert_equal public_key.errors[:key], ["is invalid. It must begin with 'ssh-rsa', 'ecdsa-sha2-nistp256', 'ecdsa-sha2-nistp384', 'ecdsa-sha2-nistp521', 'sk-ecdsa-sha2-nistp256@openssh.com'. Check that you're copying the public half of the key"]
    end
  end

  context "instrumentation" do
    test "instruments key type and size on creation" do
      public_key = build(:public_key, :sk_ed25519, user: @mojombo)
      public_key.save!
      assert_dogstats_increment "public_key", tags: ["action:create", "key_bits:256",
        "key_type:sk-ssh-ed25519@openssh.com", "member_type:user"]
    end

    test "no instrumentation increment on invalid" do
      public_key = build(:public_key, :invalid, user: @mojombo)
      refute_predicate public_key, :save
      assert_dogstats_count 0, "public_key"
    end
  end

  test "shortcode is not appended to fingerprint in GHEC", skip_enterprise: true, skip_in_multitenant_mode: true do
    emu_user = create :emu
    shortcode = emu_user.enterprise_managed_business.shortcode
    signing_key = emu_user.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
    refute_includes signing_key.fingerprint_sha256, "_#{shortcode}"
  end

  context "proxima", skip_enterprise: true do
    test "shortcode is appended to fingerprint in GHES" do
      emu_user = create :emu
      emu_business = emu_user.enterprise_managed_business
      on_multi_tenant_enterprise(tenant: emu_business) do
        signing_key = emu_user.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
        assert_includes signing_key.fingerprint_sha256, "_#{emu_business.shortcode}"
      end
    end

    test "shortcode is not displayed in fingerprint" do
      emu_user = create :emu
      emu_business = emu_user.enterprise_managed_business
      on_multi_tenant_enterprise(tenant: emu_business) do
        signing_key = emu_user.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
        refute_includes signing_key.fingerprint, "_#{emu_business.shortcode}"
      end
    end

    test "users on the same tenant cannot add the same ssh key" do
      emu_user = create :emu
      emu_business = emu_user.enterprise_managed_business
      on_multi_tenant_enterprise(tenant: emu_business) do
        user = create :user
        signing_key = emu_user.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
        assert signing_key.valid?
        assert_empty signing_key.errors

        failed_key = user.public_keys.create({ title: nil, key: @rsa_key })
        refute_predicate failed_key, :valid?
        assert_equal failed_key.errors[:key], ["is already in use"]
      end
    end

    test "users on different tenants can add the same ssh key" do
      emu_user = create :emu
      emu_business = emu_user.enterprise_managed_business
      signing_key = T.let(nil, T.untyped)
      ssh_key = T.let(nil, T.untyped)
      on_multi_tenant_enterprise(tenant: emu_business) do
        signing_key = emu_user.git_signing_ssh_public_keys.create({ title: nil, key: @rsa_key })
        assert signing_key.valid?
        assert_includes signing_key.fingerprint_sha256, "_#{emu_business.shortcode}"
      end

      emu_user2 = create :emu
      emu_business2 = emu_user2.enterprise_managed_business
      on_multi_tenant_enterprise(tenant: emu_business2) do
        ssh_key = emu_user2.public_keys.create({ title: nil, key: @rsa_key })
        assert ssh_key.valid?
        assert_includes ssh_key.fingerprint_sha256, "_#{emu_business2.shortcode}"
      end
      refute_equal ssh_key.user_id, signing_key.user_id
      assert_equal ssh_key.key, signing_key.key
      refute_equal ssh_key.fingerprint_sha256, signing_key.fingerprint_sha256
      assert_equal ssh_key.fingerprint, signing_key.fingerprint
    end
  end
end
