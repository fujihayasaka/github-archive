# typed: true
# frozen_string_literal: true

require "test_helper"

class PublicKeyTest < GitHub::TestCase
  include DogstatsTestHelpers
  include AuthenticationHelpers
  include BackgroundDeletesTestHelpers

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

  context ".repository_ids_for_policy_maker" do
    context "when the source repo is public" do
      test "scopes to repos whose access policy is set by the policymaker" do
        ids = PublicKey.repository_ids_for_policymaker(@policymaker)

        assert_includes ids, @public_source_repo.id
        refute_includes ids, @excluded_public_repo.id
      end
    end

    context "when the source repo is private" do
      test "scopes to repos whose access policy is set by the policymaker" do
        ids = PublicKey.repository_ids_for_policymaker(@policymaker)

        assert_includes ids, @private_source_repo.id
        refute_includes ids, @excluded_private_repo.id
      end
    end
  end

  test "user keys cannot be marked read only" do
    key = @mojombo.public_keys.create(key: @rsa_key, read_only: true)
    refute key.valid?
  end

  test "repo keys can be marked read only" do
    key = @repo.public_keys.create(key: @rsa_key, read_only: true)
    assert key.valid?
    assert key.read_only?
  end

  test "keys aren't read only by default" do
    key = @repo.public_keys.create(key: @rsa_key)
    refute key.read_only?
  end

  test "must have either user_id or repository_id set" do
    key = PublicKey.new key: @rsa_key
    refute key.save
    key.user = @mojombo
    assert key.save

    key.user = nil
    refute key.save
    key.repository = @repo
    assert key.save

    key.repository = nil
    key.user = nil
    assert_nil key.repository
    assert_nil key.user
    refute key.save
  end

  test "can only have either user_id or repository_id set" do
    key            = PublicKey.new(key: @rsa_key)
    key.user       = @mojombo
    key.repository = @repo

    refute key.save
    assert_equal "only one of user_id or repository_id can be assigned", key.errors[:base].first
  end

  test "must have a human user" do
    bot      = create(:integration).bot
    key      = PublicKey.new(key: @rsa_key)
    key.user = bot

    refute key.save
    assert_equal "invalid user", key.errors[:user].first
  end

  test "uses the key comment if provided with no title" do
    public_key = @mojombo.public_keys.create({ title: nil, key: "#@rsa_key jmaddox@iMac.local" })
    assert_equal "jmaddox@iMac.local", public_key.title
  end

  test "keeps the title nil if key comment isn't provided with no title" do
    public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    assert_nil public_key[:title]
  end

  test "fails for title longer than 255 characters" do
    ttl = "a" * 300
    public_key = @mojombo.public_keys.create({ title: ttl, key: @rsa_key })
    refute_predicate public_key, :valid?
  end

  test "uses the title" do
    public_key = @mojombo.public_keys.create({ title: "my server key", key: "#@rsa_key jmaddox@iMac.local" })
    assert_equal "my server key", public_key.title
  end

  test "return title as the first 25 chars of the key when title is nil" do
    public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    assert_equal "ssh-rsa AAAAB3NzaC1yc2EAAA", public_key.title
  end

  test "returns title as the actual title when title is NOT nil" do
    public_key = @mojombo.public_keys.create({ title: "my server key", key: @rsa_key })
    assert_equal "my server key", public_key.title
  end

  test "strips SSH: prefixes" do
    public_key = @mojombo.public_keys.create({ title: nil, key: "SSH:" + @rsa_key })
    assert_equal @rsa_key, public_key.key
  end

  test "prints SHA256 prefix for fingerprints" do
    public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    assert_equal "SHA256:hEbBwmrDwB9JZpczmTQnc5wbBeT+Lw+wHFmDMwRiUjI", public_key.fingerprint
  end

  test "fails if the key isn't a key" do
    public_key = @mojombo.public_keys.create({ title: "bad key", key: "Hi there, I'm not a key at all!" })
    refute_predicate public_key, :valid?
  end

  test "fails for ssh-dss keys when deprecate feature is enabled" do
    public_key = @mojombo.public_keys.create({ title: "ssh-dss key", key: @dsa_key })
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
    public_key = @mojombo.public_keys.create({ title: "ssh-dss key", key: @ill_formed_key })
    refute_predicate public_key, :valid?
    assert_equal public_key.errors[:key], ["is invalid. You must supply a key in OpenSSH public key format"]
  end

  test "catches parse errors when there is non ascii char in algorithm names" do
    ill_formed_key = "âsh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDZOPsKCabUz+RnJKMpaVFoXduLNtRHDT65ll+uBvzeBx8xl+Gp588uTs3HtHeJdBSeOZITaOK77XBZlW7TOJYHN0R0KAcK5cPaSf6mAaRDxeCHs9CCfnKlaXROW0n7HYcU52p8nSjDCsYT8N2Da9vIq96LQShji2dDXrj/kaCuHCxpNCmYvzt83GhhpCLeClLO+IS/RF9n7c6jqxwExSNacjXIEPUspk3H1QOzyhD99TeykOTKWpZCAYTFKztnxjEI6oXZd3BBtB0NvSxAiEUg5oluleB0vEDfBknkDphLqmb2+nkjJ8UZt1AhL998rH7CX4sG0O9SgtunrRJJ9BXv"
    public_key = @mojombo.public_keys.create({ title: "ssh-dss key", key: @ill_formed_key })
    refute_predicate public_key, :valid?
    assert_equal public_key.errors[:key], ["is invalid. You must supply a key in OpenSSH public key format"]
  end

  test "passes if the key is for reals" do
    public_key = @mojombo.public_keys.create({ title: "bad key", key: @test_keys[:valid] })
    assert public_key.valid?
  end

  test "passes if the key contains newlines" do
    public_key = @mojombo.public_keys.create({ title: "bad key", key: @test_keys[:valid_newlines] })
    assert public_key.valid?
  end

  test "fails if the key is a private key" do
    public_key = @mojombo.public_keys.create({ title: "bad key", key: @test_keys[:privkey] })
    refute_predicate public_key, :valid?
  end

  test "fails if the key is a compromised debian key" do
    public_key = @mojombo.public_keys.create({ title: "compromised key", key: @test_keys[:compromised] })
    refute_predicate public_key, :valid?
  end

  test "fails if the key looks legit but is corrupted" do
    public_key = @mojombo.public_keys.create({ title: "bad key", key: @test_keys[:corrupted] })
    refute_predicate public_key, :valid?
  end

  test "fails validation on invalid fingerprint" do
    # This doesn't look like a key at all, so fingerprint validation fails
    public_key = @mojombo.public_keys.create({ title: nil, key: "deadbeef" })
    assert_nil public_key.fingerprint_sha256
    refute_predicate public_key, :valid?

    # bongus second part key can't be enough to fingerprint.
    public_key = @mojombo.public_keys.create({ title: nil, key: "ssh-rsa deadbeef" })
    assert_nil public_key.fingerprint_sha256
    refute_predicate public_key, :valid?
  end

  test "fails validation if too weak" do
    public_key = @mojombo.public_keys.create({ title: "weak key", key: @test_keys[:rsa_256] })
    refute_predicate public_key, :valid?
    assert public_key.errors[:key]
  end

  test "fails validation if under 1024 bits long" do
    short_key = @mojombo.public_keys.build({ title: "weak key", key: @test_keys[:rsa_256] })
    refute_predicate short_key, :valid?
    assert_equal 1, short_key.errors[:key].length
    assert short_key.errors[:key].first.match?(/is too short/)

    long_key = @mojombo.public_keys.build(
      { title: "weak key", key: SSHKey.generate(type: "RSA", bits: 1024).ssh_public_key }
    )
    long_key.validate
    assert_predicate long_key, :valid?
  end

  test "fails validation if factorable" do
    public_key = @mojombo.public_keys.create({ title: "factorable key", key: @test_keys[:factorable_rsa] })
    refute_predicate public_key, :valid?
    assert public_key.errors[:key]
  end

  test "fails validation if infineon vulnerable" do
    public_key = @mojombo.public_keys.create({ title: "factorable key", key: @test_keys[:bad_fingerprint] })
    refute_predicate public_key, :valid?
    assert public_key.errors[:key]
  end

  test "fails validation in Proxima if the fingerprint does not have the shortcode", skip_enterprise: true do
    on_multi_tenant_enterprise do
      emu_user = create :emu
      emu_business = emu_user.enterprise_managed_business
      GitHub::CurrentTenant.set(emu_business)

      public_key = @mojombo.public_keys.create({ title: "factorable key", key: @rsa_key })
      fingerprint_with_shortcode = public_key.fingerprint_sha256
      # update fingerprint_sha to not include shortcode
      public_key.update(fingerprint_sha256: fingerprint_with_shortcode.split("_")[0])
      refute_predicate public_key, :valid?
      assert public_key.errors[:key]
    end
  end

  test "instruments creation for public_key.create event" do
    events = subscribe "public_key.create"
    key = create(:public_key, user: @mojombo)

    expected_payload = {
      public_key_id: key.id,
      title: key.title,
      key: key.key,
      fingerprint: key.fingerprint,
      created_by: "user",
      read_only: "false",
      user: key.user.login,
      user_id: key.user_id,
    }

    assert event = events.pop, "an event was expected"
    assert_equal "public_key.create", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments creation for org repo deploy_key public_key.create event" do
    events = subscribe "public_key.create"
    user = create :user, login: "a-user"
    org  = create :organization, login: "an-org", admin: user
    repo = create :repository, owner: org, name: "a-repo"
    key  = repo.public_keys.create! key: Sham.ssh_public_key

    expected_payload = {
      public_key_id: key.id,
      title: key.title,
      key: key.key,
      fingerprint: key.fingerprint,
      created_by: "user",
      read_only: "false",
      org_id: org.id,
      org: org.login,
      repo: "an-org/a-repo",
      repo_id: repo.id,
      public_repo: repo.public?,
    }

    assert event = events.pop, "an event was expected"
    assert_equal "public_key.create", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments creation for org user non-deploy_key public_key.create event does not create org event" do
    events = subscribe "public_key.create"
    user = create :user, login: "a-user"
    org  = create :organization, login: "an-org", admin: user
    key = create(:public_key, user: @mojombo)

    expected_payload = {
      public_key_id: key.id,
      title: key.title,
      key: key.key,
      fingerprint: key.fingerprint,
      created_by: "user",
      read_only: "false",
      user: key.user.login,
      user_id: key.user_id,
    }

    assert event = events.pop, "an event was expected"
    assert_equal "public_key.create", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments creation with actor context" do
    events = subscribe "public_key.create"
    user = create :user, login: "a-user"
    org  = create :organization, login: "an-org", admin: user
    repo = create :repository, owner: org, name: "a-repo"

    key = GitHub.context.push(actor: user) do
      repo.public_keys.create! key: Sham.ssh_public_key
    end

    expected_payload = {
      public_key_id: key.id,
      title: key.title,
      key: key.key,
      fingerprint: key.fingerprint,
      created_by: "user",
      read_only: "false",
      actor: user.login,
      actor_id: user.id,
      org_id: org.id,
      org: org.login,
      repo: "an-org/a-repo",
      repo_id: repo.id,
      public_repo: repo.public?,
    }

    assert event = events.pop, "an event was expected"
    assert_equal "public_key.create", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments update for public_key.update event" do
    key = create(:public_key, user: @mojombo)
    events = subscribe "public_key.update"

    expected_payload = {
      public_key_id: key.id,
      title: "Test",
      key: key.key,
      fingerprint: key.fingerprint,
      created_by: "user",
      read_only: "false",
      user: key.user.login,
      user_id: key.user_id,
    }

    key.update(title: "Test")

    assert event = events.pop, "an event was expected"
    assert_equal "public_key.update", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments deletion for public_key.delete event" do
    key = create(:public_key, user: @mojombo)
    events = subscribe "public_key.delete"

    expected_payload = {
      public_key_id: key.id,
      title: key.title,
      key: key.key,
      fingerprint: key.fingerprint,
      created_by: "user",
      read_only: "false",
      explanation: :removed_by_user,
      incident: nil,
      user: key.user.login,
      user_id: key.user_id,
    }

    key.destroy_with_explanation(:removed_by_user)

    assert event = events.pop, "an event was expected"
    assert_equal "public_key.delete", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments creation for public_key.create event with repository" do
    events = subscribe "public_key.create"
    key = create(:public_key, repository: @repo)

    expected_payload = {
      public_key_id: key.id,
      title: key.title,
      key: key.key,
      fingerprint: key.fingerprint,
      created_by: "user",
      read_only: "false",
      repo: key.repository.name_with_owner,
      repo_id: key.repository_id,
      public_repo: key.repository.public?,
    }

    assert event = events.pop, "an event was expected"
    assert_equal "public_key.create", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments creation for public_key.update event with repository" do
    key = create(:public_key, repository: @repo)
    events = subscribe "public_key.update"

    expected_payload = {
      public_key_id: key.id,
      title: "Test",
      key: key.key,
      fingerprint: key.fingerprint,
      created_by: "user",
      read_only: "false",
      repo: key.repository.name_with_owner,
      repo_id: key.repository_id,
      public_repo: key.repository.public?,
    }

    key.update(title: "Test")

    assert event = events.pop, "an event was expected"
    assert_equal "public_key.update", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments deletion for public_key.delete event with repository" do
    key = create(:public_key, repository: @repo)
    events = subscribe "public_key.delete"

    expected_payload = {
      public_key_id: key.id,
      title: key.title,
      key: key.key,
      fingerprint: key.fingerprint,
      created_by: "user",
      read_only: "false",
      explanation: :removed_by_user,
      incident: nil,
      repo: key.repository.name_with_owner,
      repo_id: key.repository_id,
      public_repo: key.repository.public?,
    }

    key.destroy_with_explanation(:removed_by_user)

    assert event = events.pop, "an event was expected"
    assert_equal "public_key.delete", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments unverify with specific reason" do
    key = create(:public_key, repository: @repo)
    events = subscribe "public_key.unverify"

    expected_payload = {
      public_key_id: key.id,
      title: key.title,
      key: key.key,
      fingerprint: key.fingerprint,
      created_by: "user",
      read_only: "false",
      explanation: :stale,
      repo: key.repository.name_with_owner,
      repo_id: key.repository_id,
      public_repo: key.repository.public?,
    }

    key.unverify(:stale)

    assert event = events.pop, "an event was expected"
    assert_equal "public_key.unverify", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments unverification errors" do
    key = create(:public_key, repository: @repo)
    key.update_attribute(:key, "bogus")
    key = PublicKey.find(key.id)
    events = subscribe "public_key.unverification_failure"

    expected_payload = {
      public_key_id: key.id,
      title: key.title,
      key: key.key,
      fingerprint: key.fingerprint,
      created_by: "user",
      read_only: "false",
      reason: "key is invalid. You must supply a key in OpenSSH public key format",
      repo: key.repository.name_with_owner,
      repo_id: key.repository_id,
      public_repo: key.repository.public?,
    }

    key.unverify(:stale)

    assert event = events.pop, "an event was expected"
    assert_equal "public_key.unverification_failure", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments verify" do
    key = create(:public_key, repository: @repo)
    events = subscribe "public_key.verify"

    expected_payload = {
      public_key_id: key.id,
      title: key.title,
      key: key.key,
      fingerprint: key.fingerprint,
      created_by: "user",
      read_only: "false",
      repo: key.repository.name_with_owner,
      repo_id: key.repository_id,
      public_repo: key.repository.public?,
    }

    key.verify(@mojumbo)

    assert event = events.pop, "an event was expected"
    assert_equal "public_key.verify", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments verification errors" do
    key = create(:public_key, repository: @repo)
    key.unverify(:stale)
    key.update_attribute(:key, "bogus")
    key = PublicKey.find(key.id)
    events = subscribe "public_key.verification_failure"

    expected_payload = {
      public_key_id: key.id,
      title: key.title,
      key: key.key,
      fingerprint: key.fingerprint,
      created_by: "user",
      read_only: "false",
      reason: "key is invalid. You must supply a key in OpenSSH public key format",
      repo: key.repository.name_with_owner,
      repo_id: key.repository_id,
      public_repo: key.repository.public?,
    }

    key.verify(@mojombo)

    assert event = events.pop, "an event was expected"
    assert_equal "public_key.verification_failure", event.name
    assert_equal expected_payload, event.payload
  end

  context "#unverify" do
    test "records the reason the key was unverified" do
      key = @mojombo.public_keys.create_with_verification \
        verifier: @mojombo, key: Sham.ssh_public_key
      assert_predicate key, :verified?

      key.unverify(:stale)
      key.reload

      assert_equal "stale", key.unverification_reason
      refute_predicate key, :verified?
    end
  end

  context "#verify" do
    test "records the verifier and the verification timestamp" do
      public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
      assert_equal false, public_key.verified?
      assert_equal true, public_key.verify(@mojombo)
      assert_equal @mojombo, public_key.verifier
      assert public_key.verified_at.is_a?(Time)
    end

    test "works for badly-formatted keys" do
      bad_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
      bad_key.key = "#@rsa_key my name is <bob@aol.com>\n"
      assert_equal true, bad_key.save(validate: false)

      assert_equal true, bad_key.verify(@mojombo)
      assert_equal @rsa_key, bad_key.key
    end

    test "doesn't result in update email" do
      public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
      ActionMailer::Base.deliveries.clear

      public_key.verify(@mojombo)

      assert ActionMailer::Base.deliveries.empty?
    end

    test "allows previously-unverified key of unknown origin to act as if it were created directly by the user" do
      key = @mojombo.public_keys.create!(key: Sham.ssh_public_key)
      key.created_by = "unknown"
      key.save!
      assert_predicate key, :created_by_unknown?
      refute_predicate key, :verified?

      success = key.verify(@mojombo)
      assert_equal true, success

      assert_predicate key, :created_by_user?
      assert_equal @mojombo, key.verifier
      assert_predicate key, :verified?
    end

    test "allows previously-verified key of unknown origin to act as if it were created directly by the user" do
      key = @mojombo.public_keys.create_with_verification \
        verifier: @mojombo, key: Sham.ssh_public_key
      key.created_by = "unknown"
      key.save!
      assert_predicate key, :created_by_unknown?
      assert_predicate key, :verified?

      success = key.verify(@mojombo)
      assert_equal true, success

      assert_predicate key, :created_by_user?
      assert_equal @mojombo, key.verifier
      assert_predicate key, :verified?
    end

    test "does not change origin info for a key created by a user's personal access token" do
      personal_token = create(:personal_token_oauth_access, user: @mojombo)
      key = @mojombo.public_keys.create_with_verification \
        verifier: @owner,
        key: Sham.ssh_public_key,
        oauth_authorization: personal_token.authorization
      assert_equal "oauth_access", key.created_by
      assert_predicate key, :created_by_user?

      success = key.verify(@mojombo)
      assert_equal true, success

      assert_predicate key, :created_by_user?
    end

    test "does not change origin info for a key created by an OAuth application" do
      oauth_access = make_oauth(@mojombo)
      key = @mojombo.public_keys.create_with_verification \
        verifier: @owner, key: Sham.ssh_public_key,
        oauth_authorization: oauth_access.authorization
      assert_predicate key, :created_by_oauth_application?

      success = key.verify(@mojombo)
      assert_equal true, success

      assert_predicate key, :created_by_oauth_application?
    end
  end

  context "#adminable_by?" do
    test "returns true for a user key that belongs to the user" do
      owner = create(:user)
      key   = owner.public_keys.create! key: Sham.ssh_public_key

      assert key.adminable_by?(owner)
    end

    test "returns false for a user key that belongs to another user" do
      owner = create(:user)
      key   = owner.public_keys.create! key: Sham.ssh_public_key

      refute key.adminable_by?(create(:user))
    end

    test "returns true for a deploy key in a repo that is adminable by the user" do
      user = create :user, login: "a-user"
      org  = create :organization, login: "an-org", admin: user
      repo = create :repository, owner: org, name: "a-repo"
      key  = repo.public_keys.create! key: Sham.ssh_public_key

      assert key.adminable_by?(user)
    end

    test "returns false for a deploy key in a repo that is not adminable by the user" do
      user = create :user, login: "a-user"
      org  = create :organization, login: "an-org"
      team = create :team, organization: org, permission: "pull"
      repo = create :repository, owner: org, name: "a-repo"
      key  = repo.public_keys.create! key: Sham.ssh_public_key

      team.add_member(user)
      team.add_repository(repo, :pull)
      assert repo.pullable_by?(user)

      refute key.adminable_by?(user)
    end
  end

  test "unverifying doesn't result in update email" do
    public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    public_key.verify(@mojombo)
    ActionMailer::Base.deliveries.clear

    public_key.unverify(:stale)

    assert ActionMailer::Base.deliveries.empty?
  end

  test "renaming a user doesn't result in update email" do
    public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    ActionMailer::Base.deliveries.clear

    @mojombo.rename!("fakemojombo")

    assert ActionMailer::Base.deliveries.empty?
  end

  test "renaming a repository doesn't result in an update email" do
    public_key = @repo.public_keys.create!({ title: nil, key: @rsa_key })
    ActionMailer::Base.deliveries.clear

    assert @repo.rename("something")

    assert ActionMailer::Base.deliveries.empty?
  end

  test "does not allow duplicate keys" do
    public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    assert public_key.valid?

    public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    refute_predicate public_key, :valid?
    assert_match /already in use/, public_key.errors[:key].first
  end

  test "does not allow a user to create a public key if another user has a signing key with the same fingerprint" do
    other_user = create(:user)
    other_user.git_signing_ssh_public_keys.create!({ title: nil, key: @rsa_key })

    public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    refute_predicate public_key, :valid?
    assert_match /already in use/, public_key.errors[:key].first
  end

  test "allows a user to create a public key if they have a signing key with the same fingerprint" do
    @mojombo.git_signing_ssh_public_keys.create!({ title: nil, key: @rsa_key })

    public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    assert public_key.valid?
  end

  test "a deploy key is not valid if it has the same fingerprint as a user's signing key" do
    other_user = create(:user)
    other_user.git_signing_ssh_public_keys.create!({ title: nil, key: @rsa_key })

    deploy_key = @repo.public_keys.create({ title: nil, key: @rsa_key })
    refute_predicate deploy_key, :valid?
    assert_match /already in use/, deploy_key.errors[:key].first
  end

  test "links public keys to previously revoked organization credentials with the same fingerprint" do
    public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    assert public_key.valid?

    org = create(:organization, plan: "bronze")
    org.add_member(@mojombo)

    auth = Organization::CredentialAuthorization.grant(organization: org, credential: public_key, actor: @mojombo)
    assert auth, "should have granted credential authorization to #{org} for #{public_key}"

    assert Organization::CredentialAuthorization.revoke(organization: org, credential: public_key, actor: org.admins.first),
      "should have revoked credential authorization to #{org} for #{public_key}"

    public_key.destroy

    new_key = @mojombo.public_keys.create({ title: "same as the old key", key: @rsa_key })

    assert_equal new_key.id, auth.reload.credential_id,
      "should have updated the associated credential authorization based on the new key's fingerprint"
  end

  # https://github.com/github/github/issues/82987
  test "removes non-revoked organization authorization credentials when the public key is destroyed" do
    public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    assert public_key.valid?

    org = create(:organization, plan: "bronze")
    org.add_member(@mojombo)

    # Grant credential authorization to the public key
    auth = Organization::CredentialAuthorization.grant(organization: org, credential: public_key, actor: @mojombo)
    assert auth, "should have granted credential authorization to #{org} for #{public_key}"

    # Destroying the public key should destroy the associated credential
    # authorization
    public_key.destroy

    credentials = Organization::CredentialAuthorization.by_organization_credential(
      organization: org,
      credential: public_key,
    )
    assert_predicate credentials, :none?

    # It should be possible to grant credential authorization access to the same key
    new_key = @mojombo.public_keys.create({ title: "same as the old key", key: @rsa_key })

    auth = Organization::CredentialAuthorization.grant(organization: org, credential: new_key, actor: @mojombo)
    assert auth, "should have granted credential authorization to #{org} for #{new_key} again"
  end

  # https://github.com/github/github/issues/82987
  test "does not remove revoked organization authorization credentials when the public key is destroyed" do
    public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    assert public_key.valid?

    org = create(:organization, plan: "bronze")
    org.add_member(@mojombo)

    # Grant credential authorization to the public key
    auth = Organization::CredentialAuthorization.grant(organization: org, credential: public_key, actor: @mojombo)
    assert auth, "should have granted credential authorization to #{org} for #{public_key}"

    # Revoke the credential authorization associted with this public key
    assert Organization::CredentialAuthorization.revoke(organization: org, credential: public_key, actor: org.admins.first),
      "should have revoked credential authorization to #{org} for #{public_key}"

    # Destroying the public key should *not* destroy the associated credential
    # authorization
    public_key.destroy

    credentials = Organization::CredentialAuthorization.revoked.by_organization_credential(
      organization: org,
      credential: public_key,
    )
    assert_includes credentials, auth
  end

  test "scopes the list of credential authorization by credential_type" do
    public_key = @mojombo.public_keys.create(title: nil, key: @rsa_key)
    assert_predicate public_key, :valid?

    org = create(:organization, plan: "bronze")
    org.add_member(@mojombo)

    # Grant credential authorization to the public key
    public_key_grant = Organization::CredentialAuthorization.grant(organization: org, credential: public_key, actor: @mojombo)
    assert public_key_grant, "should have granted credential authorization to #{org} for #{public_key}"

    # Grant credential authorization to the personal access token
    pat = create(:personal_token_oauth_access, id: public_key.id, user: @mojombo)
    pat_grant = Organization::CredentialAuthorization.grant(organization: org, credential: pat, actor: @mojombo)
    assert pat_grant, "should have granted credential authorization to #{org} for #{pat}"

    refute_includes public_key.active_org_credential_authorizations, pat_grant
  end

  test "ignores duplicates of badly formatted keys" do
    bad_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    bad_key.key = "#@rsa_key my name is <bob@aol.com>\n"
    assert_equal true, bad_key.save(validate: false)

    public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    refute_predicate public_key, :valid?
    assert_match /already in use/, public_key.errors[:key].first
  end

  test "checks uniqueness on save" do
    public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    public_key.save!
  end

  # skip because EMUs are no eligible to become staff
  test "big red button nukes public keys", skip_with_all_emus: true do
    add_as_employee(@mojombo)
    @mojombo.gh_role = "staff"
    @mojombo.public_keys.create({ title: nil, key: @rsa_key })
    @mojombo.staff_revoke

    assert @mojombo.public_keys.empty?
  end

  test "sends notification when a key is added" do
    AccountMailer.expects(:public_key_added).returns(stub(deliver_later: nil))
    add_as_employee(@mojombo)
    @mojombo.update_attribute :gh_role, "staff"
    @mojombo.public_keys.create({ title: nil, key: @rsa_key })
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  test "sends deploy key emails for non-org repos to the owner's default email address" do
    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      user = create(:user)
      org  = create(:organization, admin: user)
      repo = create(:repository, owner: user)

      deliveries.clear
      assert_equal 0, deliveries.size

      create(:public_key, repository: repo)

      assert_equal 1, deliveries.size
      assert_equal [user.email], deliveries[0].bcc
      assert_equal "[GitHub] A new public key was added to #{repo.name_with_owner}", deliveries[0].subject
    end
  end

  test "supresses deploy key emails when repository is being imported" do
    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      user = create(:user)
      org  = create(:organization, admin: user)
      repo = create(:repository, owner: user)

      repo.stubs(:is_importing?).returns(true)

      deliveries.clear
      assert_equal 0, deliveries.size

      create(:public_key, repository: repo)

      assert_equal 0, deliveries.size
    end
  end

  test "sends deploy keys for orgs to the proper newsies org email address" do
    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      user1 = create(:user)
      user2 = create(:user)

      org1  = create(:organization, admin: user1).reload
      org1.add_admin(user2)
      org2  = create(:organization, admin: user1)

      repo1 = create(:repository, owner: org1)
      repo2 = create(:repository, owner: org2)

      user1_email1 = "user1@org1.com"
      user1_email2 = "user1@org2.com"
      user2_email  = "user2@org1.com"

      GitHub.newsies.get_and_update_settings(user1) do |s|
        s.email(org1, user1_email1)
        s.email(org2, user1_email2)
      end

      GitHub.newsies.get_and_update_settings(user2) do |s|
        s.email(org1, user2_email)
      end

      deliveries.clear
      assert_equal 0, deliveries.size

      create(:public_key, repository: repo1)
      create(:public_key, repository: repo2)

      assert_equal 2, deliveries.size
      assert_equal [user1_email1, user2_email], deliveries[0].bcc.sort
      assert_equal [user1_email2],              deliveries[1].bcc
      assert_equal "[GitHub] A new public key was added to #{repo1.name_with_owner}", deliveries[0].subject
      assert_equal "[GitHub] A new public key was added to #{repo2.name_with_owner}", deliveries[1].subject
    end
  end

  test "#access for key that has never been accessed updates accessed_at" do
    perform_enqueued_jobs(only: [PublicKeyAccessJob]) do
      with_cache_enabled do
        Timecop.freeze(Time.zone.now) do
          public_key = create(:public_key, {
            user: @mojombo,
            key: @rsa_key,
            title: nil,
            accessed_at: nil,
          })
          assert_nil GitHub.cache.get("public_keys:last_accessed:#{public_key.id}")

          public_key.access
          public_key.reload
          assert_equal Time.zone.now.to_i, public_key.accessed_at.to_i
          assert_equal Time.zone.now, GitHub.cache.get("public_keys:last_accessed:#{public_key.id}")
        end
      end
    end
  end

  test "#access instruments public_key.access" do
    GitHub.stubs(:stats).returns(MemoryStatsD.new)
    perform_enqueued_jobs(only: [PublicKeyAccessJob]) do
      with_cache_enabled do
        Timecop.freeze(Time.zone.now) do
          public_key = create(:public_key, {
            user: @mojombo,
            key: @rsa_key,
            title: nil,
            accessed_at: nil,
          })
          assert_nil GitHub.cache.get("public_keys:last_accessed:#{public_key.id}")

          public_key.access
          public_key.reload
          assert_equal Time.zone.now.to_i, public_key.accessed_at.to_i
          assert_equal Time.zone.now, GitHub.cache.get("public_keys:last_accessed:#{public_key.id}")
          assert_equal 1, GitHub.stats.increments["public_key.access.count"] if GitHub.enterprise?
        end
      end
    end
  end

  test "#access for key that has not been updated in throttling period updates accessed_at" do
    perform_enqueued_jobs(only: [PublicKeyAccessJob]) do
      with_cache_enabled do
        Timecop.freeze(Time.zone.now) do
          public_key = create(:public_key, {
            user: @mojombo,
            key: @rsa_key,
            title: nil,
            accessed_at: Time.zone.now - PublicKey::ACCESS_THROTTLING - 1,
          })
          assert_nil GitHub.cache.get("public_keys:last_accessed:#{public_key.id}")

          public_key.access
          public_key.reload
          assert_equal Time.zone.now.to_i, public_key.accessed_at.to_i
          assert_equal Time.zone.now, GitHub.cache.get("public_keys:last_accessed:#{public_key.id}")
        end
      end
    end
  end

  test "#access for key that exists in memcached does not update accessed_at" do
    with_cache_enabled do
      now = Time.at(1542131343)
      Timecop.freeze(now) do
        accessed_at = now - PublicKey::ACCESS_THROTTLING - 1
        public_key = create(:public_key, {
          user: @mojombo,
          key: @rsa_key,
          title: nil,
          accessed_at: accessed_at,
        })
        GitHub.cache.add("public_keys:last_accessed:#{public_key.id}", accessed_at, PublicKey::ACCESS_THROTTLING.to_i)

        public_key.access
        public_key.reload
        assert_equal accessed_at.to_i, public_key.accessed_at.to_i
        assert_equal accessed_at, GitHub.cache.get("public_keys:last_accessed:#{public_key.id}")
      end
    end
  end

  test "#access for key has been accessed in throttling period does not update accessed_at in mysql or memcached" do
    with_cache_enabled do
      Timecop.freeze(Time.zone.now) do
        accessed_at = Time.zone.now - PublicKey::ACCESS_THROTTLING + 1
        public_key = create(:public_key, {
          user: @mojombo,
          key: @rsa_key,
          title: nil,
          accessed_at: accessed_at,
        })

        public_key.access
        public_key.reload
        assert_equal accessed_at.to_i, public_key.accessed_at.to_i
        assert_nil GitHub.cache.get("public_keys:last_accessed:#{public_key.id}")
      end
    end
  end

  test "#access enqueues job to update accessed_at" do
    with_cache_enabled do
      Timecop.freeze(Time.zone.now) do
        public_key = create(:public_key, {
          user: @mojombo,
          key: @rsa_key,
          title: nil,
          accessed_at: nil,
        })

        assert_nil GitHub.cache.get("public_keys:last_accessed:#{public_key.id}")
        public_key.access

        assert_enqueued_jobs 1, only: PublicKeyAccessJob, queue: :public_key_accesses
        public_key.reload
        assert_nil public_key.accessed_at
        assert_equal Time.zone.now, GitHub.cache.get("public_keys:last_accessed:#{public_key.id}")
      end
    end
  end

  test "#access! also bumps authorization with same time" do
    perform_enqueued_jobs(only: [OauthAuthorizationBumpJob]) do
      with_cache_enabled do
        # Call ".floor" to remove milliseconds, so we don't get flakiness from MySQL rounding up/down to
        # nearest second
        Timecop.freeze(Time.zone.now.floor) do
          now = 4.days.ago
          oauth_authorization = create(:oauth_authorization, accessed_at: nil)
          public_key = create(:public_key, {
            user: @mojombo,
            key: @rsa_key,
            title: nil,
            accessed_at: nil,
            oauth_authorization: oauth_authorization,
          })

          public_key.access!(now)

          assert_equal now.to_i, public_key.reload.accessed_at.to_i
          assert_equal now.to_i, oauth_authorization.reload.accessed_at.to_i
        end
      end
    end
  end

  context "determining how a key was created" do
    test "identifying a key created directly by a user" do
      key = @mojombo.public_keys.create_with_verification \
        verifier: @mojombo, key: Sham.ssh_public_key

      assert_equal "user", key.created_by
      assert key.created_by_user?
      refute key.created_by_oauth_application?
      refute key.created_by_unknown?
    end

    test "identifying a key created by a user's personal access token" do
      personal_token = create(:personal_token_oauth_access, user: @mojombo)
      key = @mojombo.public_keys.create_with_verification \
        verifier: @owner, key: Sham.ssh_public_key,
        oauth_authorization: personal_token.authorization

      assert_equal "oauth_access", key.created_by
      assert key.created_by_user?
      assert_nil key.oauth_application_id
      refute key.created_by_oauth_application?
      refute key.created_by_unknown?
    end

    test "identifying a key created by an OAuth token that belongs to an OAuth application" do
      oauth_access = make_oauth(@mojombo)
      key = @mojombo.public_keys.create_with_verification \
        verifier: @owner, key: Sham.ssh_public_key,
        oauth_authorization: oauth_access.authorization

      assert_equal "oauth_access", key.created_by
      refute key.created_by_user?
      assert key.created_by_oauth_application?
      assert_equal oauth_access.application.id, key.oauth_application_id
      refute key.created_by_unknown?
    end

    test "identifying a key created before we started associating OAuth tokens with the keys they create" do
      key = @mojombo.public_keys.create_with_verification \
        verifier: @mojombo, key: Sham.ssh_public_key
      key.created_by = "unknown"
      key.save!

      assert_equal "unknown", key.created_by
      refute key.created_by_user?
      refute key.created_by_oauth_application?
      assert key.created_by_unknown?
    end

    test "replaces invalid #created_by value with default value" do
      key = PublicKey.new
      key.created_by = "bogus"

      assert_equal "bogus", key.created_by
      key.valid? # trigger validation
      assert_equal "user", key.created_by
    end

    test "validates data consistency for key created by user" do
      user = create(:user)
      key = create :public_key, user: user
      assert key.valid?

      oauth_access = make_oauth(user)
      key.oauth_authorization = oauth_access.authorization
      key.created_by = "user"
      refute key.valid?

      key.oauth_authorization = nil
      key.created_by = "user"
      assert key.valid?
    end

    test "validates data consistency for key created by OAuth token" do
      user = create(:user)
      oauth_access = make_oauth(user)
      key = create :public_key, user: user
      assert key.valid?

      key.created_by = "oauth_access"
      refute key.valid?

      key.oauth_authorization = oauth_access.authorization
      key.created_by = nil
      refute key.valid?

      key.oauth_authorization = oauth_access.authorization
      key.created_by = "oauth_access"
      assert key.valid?
    end

    test "validates data consistency for key of unknown origin" do
      user = create(:user)
      key = create :public_key, user: user
      assert key.valid?

      oauth_access = make_oauth(user)
      key.oauth_authorization = oauth_access.authorization
      key.created_by = "unknown"
      refute key.valid?

      key.oauth_authorization = nil
      key.created_by = "unknown"
      assert key.valid?
    end
  end

  context "#can_verify_account_ownership?" do
    test "cannot verify account ownership if it is unverified" do
      user = create(:user)
      key = create :public_key, user: user
      key.unverify(:stale)

      refute key.can_verify_account_ownership?
    end

    test "cannot verify account ownership if it was created by an oauth application" do
      user = create(:user)
      key = create :public_key, user: user
      key.verify(@mojombo)
      oauth_access = make_oauth(user)
      key.oauth_authorization = oauth_access.authorization

      refute key.can_verify_account_ownership?
    end

    test "cannot verify account ownership if it was created by an integration" do
      user = create(:user)
      repo = create(:repository, owner: user)
      integration = create(:integration)
      authorization = integration.grant(user).authorization
      key = create(:public_key, repository: repo, oauth_authorization: authorization)
      key.verify(user)

      refute key.can_verify_account_ownership?
    end

    test "can verify account ownership if it is verified and was not created by an oauth application" do
      user = create(:user)
      key = create :public_key, user: user
      key.verify(@mojombo)

      assert key.can_verify_account_ownership?
    end

    test "can verify account ownership if it is verified and was created by a capable app" do
      user = create(:user)
      key = create :public_key, user: user
      key.verify(@mojombo)

      oauth_access = make_oauth(user)
      key.oauth_authorization = oauth_access.authorization
      desktop_application = create_internal_app_with_capabilities(type: :oauth_application, capabilities: { verify_account_ownership: true }, options: { user: user })
      key.oauth_authorization.application = desktop_application

      assert key.can_verify_account_ownership?
    end
  end

  context "#ability_delegate" do
    test "returns a User, for a user key" do
      user = create(:user)
      key = create :public_key, user: user

      assert_equal user, key.ability_delegate
    end

    test "returns the repository owner, for a repo key" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      key = create :public_key, repository: repo

      assert_equal org, key.ability_delegate
    end
  end

  context "fips mode" do
    test "allows ed25519 keys not in FIPS mode" do
      GitHub.stubs(:fips_mode?).returns(false)
      public_key = @mojombo.public_keys.create(title: "ed25519 key", key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINzroZG/Uhzz7Pwjr8Q2JlqVHcsC1yKdTm8IdQz2zX6j dirkjan@dbussink.archimedes.bussink.me")
      assert_predicate public_key, :valid?
    end

    test "blocks ed25519 keys in FIPS mode" do
      GitHub.stubs(:fips_mode?).returns(true)
      public_key = @mojombo.public_keys.create(title: "ed25519 key", key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINzroZG/Uhzz7Pwjr8Q2JlqVHcsC1yKdTm8IdQz2zX6j dirkjan@dbussink.archimedes.bussink.me")
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

  context "ssh keys creation" do
    context "in GHEC", skip_enterprise: true, skip_in_multitenant_mode: true do
      test "shortcode is not appended to fingerprint" do

        emu_user = create :emu
        shortcode = emu_user.enterprise_managed_business.shortcode
        public_key = emu_user.public_keys.create({ title: nil, key: @rsa_key })
        refute_includes public_key.fingerprint_sha256, "_#{shortcode}"
      end

      test "two users cannot add the same ssh key" do
        user = create :user

        public_key = @mojombo.public_keys.create({ title: nil, key: @rsa_key })
        failed_key = user.public_keys.create({ title: nil, key: @rsa_key })

        assert public_key.valid?
        assert_empty public_key.errors

        refute_predicate failed_key, :valid?
        assert_equal failed_key.errors[:key], ["is already in use"]
      end
    end
    context "in Proxima", skip_enterprise: true do
      test "shortcode is appended to fingerprint" do
        on_multi_tenant_enterprise do
          emu_user = create :emu
          emu_business = emu_user.enterprise_managed_business
          GitHub::CurrentTenant.set(emu_business)

          public_key = emu_user.public_keys.create({ title: nil, key: @rsa_key })
          assert_includes public_key.fingerprint_sha256, "_#{emu_business.shortcode}"
        end
      end

      test "shortcode is not displayed in fingerprint" do
        on_multi_tenant_enterprise do
          emu_user = create :emu
          emu_business = emu_user.enterprise_managed_business
          GitHub::CurrentTenant.set(emu_business)

          public_key = emu_user.public_keys.create({ title: nil, key: @rsa_key })
          refute_includes public_key.fingerprint, "_#{emu_business.shortcode}"
        end
      end

      test "two users on two different tenants on the same stamp can add the same ssh key" do
        public_key = T.let(nil, T.nilable(PublicKey))
        public_key2 = T.let(nil, T.nilable(PublicKey))
        on_multi_tenant_enterprise do
          emu_user = create :emu
          GitHub::CurrentTenant.set(emu_user.enterprise_managed_business)

          public_key = emu_user.public_keys.create({ title: nil, key: @rsa_key })
          assert_includes public_key.fingerprint_sha256, "_#{emu_user.enterprise_managed_business.shortcode}"
        end

        on_multi_tenant_enterprise do
          emu_user2 = create :emu
          GitHub::CurrentTenant.set(emu_user2.enterprise_managed_business)

          public_key2 = emu_user2.public_keys.create({ title: nil, key: @rsa_key })
          assert_includes public_key2.fingerprint_sha256, "_#{emu_user2.enterprise_managed_business.shortcode}"
        end
        refute_equal public_key&.user_id, public_key2&.user_id
        assert_equal public_key&.key, public_key2&.key
        assert_equal public_key&.fingerprint, public_key2&.fingerprint
      end

      test "two users on the same tenants cannot add the same ssh key" do
        on_multi_tenant_enterprise do
          emu_user = create :emu
          emu_business = emu_user.enterprise_managed_business
          GitHub::CurrentTenant.set(emu_business)

          user = create :user
          public_key = emu_user.public_keys.create({ title: nil, key: @rsa_key })
          assert_includes public_key.fingerprint_sha256, "_#{emu_business.shortcode}"

          failed_key = user.public_keys.create({ title: nil, key: @rsa_key })
          refute_predicate failed_key, :valid?
          assert_equal failed_key.errors[:key], ["is already in use"]

          assert public_key.valid?
          assert_empty public_key.errors
        end
      end

      test "fingerprint includes shortcode when authorized for an organization" do
        on_multi_tenant_enterprise do
          emu_user = create :emu
          emu_business = emu_user.enterprise_managed_business
          GitHub::CurrentTenant.set(emu_business)

          public_key = emu_user.public_keys.create(title: nil, key: @rsa_key)
          assert_predicate public_key, :valid?
          assert_includes public_key.fingerprint_sha256, "_#{emu_user.enterprise_managed_business.shortcode}"

          org = create(:organization, plan: "bronze")
          org.add_member(emu_user)

          # Grant credential authorization to the public key
          public_key_grant = Organization::CredentialAuthorization.grant(organization: org, credential: public_key, actor: emu_user)
          assert_includes public_key_grant.fingerprint_sha256, "_#{emu_user.enterprise_managed_business.shortcode}"
        end
      end
    end
  end

  test "is deleted with repository" do
    key = PublicKey.create!(key: @test_keys[:valid], repository: @repo)
    other_key = PublicKey.create!(key: @rsa_key, repository: @public_source_repo)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [key]
      config.expect_not_destroyed = [other_key]
    end
  end
end


if GitHub.enterprise?
  class PublicKeyGHESTest < GitHub::TestCase
    include DogstatsTestHelpers

    # NOTE: includes AuthenticationHelpers
    include AuthenticationHelpers::LDAP

    setup_once { LdapHelper.setup_ldap_authentication }
    teardown_once { LdapHelper.teardown_ldap_authentication }

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
    end

    ldap_test "is verified when managed externally by LDAP" do
      @mojombo.map_ldap_entry "uid=mojombo,ou=users,dc=github,dc=com"
      sync = GitHub::LDAP::UserSync.new

      sync_user_keys do
        sync.perform(@mojombo)
        key = @mojombo.public_keys.first
        assert_predicate key, :verified?
      end
    end

    ldap_test "is not verified for user not LDAP Synced when managed externally by LDAP" do
      refute @mojombo.ldap_mapped?
      key = @mojombo.public_keys.create(title: nil, key: @rsa_key)

      sync_user_keys do
        refute_predicate key, :verified?
      end
    end

    ldap_test "deploy key is not verified when user SSH Keys are managed externally by LDAP" do
      key = @repo.public_keys.create!(title: nil, key: @rsa_key)
      sync_user_keys do
        refute_predicate key, :verified?
      end
    end
  end
end
