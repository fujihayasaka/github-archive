# typed: true
# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < GitHub::TestCase
  fixtures do
    disable_feature_flag(:actions_default_workflow_permissions_new_repos)

    @repo  = create(:repository)
    @owner = @repo.owner
    @user  = create(:user)
    @org   = create(:organization)
    @business = create(:business)
  end

  setup do
    @old_lfs = GitHub.git_lfs_enabled

    # make sure we're not memoizing any entries with the heaviest of hands
    [GitHub, @repo, @user, @owner, @org].each do |fixture|
      fixture.config.reset
    end

    Configuration::Entry.delete_all
  end

  teardown do
    GitHub.git_lfs_enabled = @old_lfs
  end

  test "get/set/delete a value on a repository" do
    val = "someval"

    assert_nil @repo.config.get("key")

    @repo.config.set "key", val, @user
    assert_equal val, @repo.config.get("key")

    @repo.config.delete "key"
    assert_nil @repo.config.get("key")
  end

  test "get/set/delete a value on a owner" do
    val = "ownerval"

    assert_nil @owner.config.get("key")

    @owner.config.set "key", val, @user
    assert_equal val, @owner.config.get("key")

    @owner.config.delete "key"
    assert_nil @owner.config.get("key")
  end

  test "get/set/delete a value on an org" do
    val = "ownerval"

    assert_nil @org.config.get("key")

    @org.config.set "key", val, @user
    assert_equal val, @org.config.get("key")

    @org.config.delete "key"
    assert_nil @org.config.get("key")
  end

  test "get/set/delete a global value" do
    val = "globalval"

    assert_nil GitHub.config.get("key")

    GitHub.config.set "key", val, @user
    assert_equal val, GitHub.config.get("key")

    GitHub.config.delete "key"
    assert_nil GitHub.config.get("key")
  end

  test "get/set an int value" do
    val = 3

    assert_nil @repo.config.get("key")

    @repo.config.set "key", val, @user
    assert_equal val, @repo.config.int("key")
    assert_equal val.to_s, @repo.config.get("key")
  end

  test "get a missing int value" do
    assert_nil @repo.config.get("key")
    assert_nil @repo.config.int("key")
  end

  test "get a bogus int value" do
    @repo.config.set "key", "val", @user
    assert_equal 0, @repo.config.int("key")
  end

  test "enable and test a flag value" do
    @repo.config.disable("key", @user)
    refute @repo.config.enabled?("key")

    @repo.config.enable("key", @user)
    assert @repo.config.enabled?("key")
  end

  test "enable! overrides" do
    @repo.config.disable("key", @user)
    refute @repo.config.enabled?("key")

    @owner.config.enable!("key", @user)

    @repo.config.reset
    assert @repo.config.enabled?("key")
  end

  test "disable and test a flag value" do
    @repo.config.enable("key", @user)
    assert @repo.config.enabled?("key")

    @repo.config.disable("key", @user)
    refute @repo.config.enabled?("key")
  end

  test "disable! overrides" do
    @repo.config.enable("key", @user)
    assert @repo.config.enabled?("key")

    @owner.config.disable!("key", @user)

    @repo.config.reset
    refute @repo.config.enabled?("key")
  end

  test "enable resets final if used after disable!" do
    @owner.config.disable!("key", @user)
    @owner.config.enable("key", @user)

    refute @owner.config.final?("key")
  end

  test "set returns a value indicating whether the entry was updated" do
    assert @owner.config.set("key", "value", @user)
    refute @owner.config.set("key", "value", @user)
  end

  test "set is resilient against race conditions" do
    # This is the same record as @owner but a different object in memory,
    # representing some other process attempting to set the same configuration.
    @same_owner = @owner.class.find(@owner.id)

    # These get calls memoize the configuration entries for each object.
    assert_nil @owner.config.get("key")
    assert_nil @same_owner.config.get("key")

    assert @owner.config.set("key", "value", @user)
    refute @same_owner.config.set("key", "value", @user)

    assert_equal "value", @owner.config.get("key")
    assert_equal "value", @same_owner.config.get("key")
  end

  test "set! returns a value indicating whether the entry was updated" do
    assert @owner.config.set!("key", "value", @user)
    refute @owner.config.set!("key", "value", @user)
    assert @owner.config.set!("key", "value", @user, false)
    refute @owner.config.set!("key", "value", @user, false)
  end

  test "enable returns a value indicating whether the entry was updated" do
    assert @owner.config.enable("key", @user)
    refute @owner.config.enable("key", @user)
  end

  test "enable! returns a value indicating whether the entry was updated" do
    assert @owner.config.enable!("key", @user)
    refute @owner.config.enable!("key", @user)
    assert @owner.config.enable!("key", @user, false)
    refute @owner.config.enable!("key", @user, false)
  end

  test "disable returns a value indicating whether the entry was updated" do
    assert @owner.config.disable("key", @user)
    refute @owner.config.disable("key", @user)
  end

  test "disable! returns a value indicating whether the entry was updated" do
    assert @owner.config.disable!("key", @user)
    refute @owner.config.disable!("key", @user)
    assert @owner.config.disable!("key", @user, false)
    refute @owner.config.disable!("key", @user, false)
  end

  test "delete returns a value indicating whether an entry was deleted" do
    @owner.config.enable("key", @user)
    @repo.config.enable("key", @user)

    assert @repo.config.delete("key", @user)
    refute @repo.config.delete("key", @user)
  end

  test "delete is resilient against race conditions" do
    # This is the same record as @owner but a different object in memory,
    # representing some other process attempting to set the same configuration.
    @same_owner = @owner.class.find(@owner.id)
    @owner.config.set("key", "value", @user)

    # These get calls memoize the configuration entries for each object.
    assert_equal "value", @owner.config.get("key")
    assert_equal "value", @same_owner.config.get("key")

    assert @owner.config.delete("key", @user)
    refute @same_owner.config.delete("key", @user)

    assert_nil @owner.config.get("key")
    assert_nil @same_owner.config.get("key")
  end

  test "delete fails if entry destruction fails" do
    @owner.config.set("key", "value", @user)

    # Simulate failed record destruction.
    Configuration::Entry.any_instance.stubs(:destroy_row).raises(ActiveRecord::RecordNotDestroyed)

    assert_raises(ActiveRecord::RecordNotDestroyed) do
      @owner.config.delete("key", @user)
    end
  end

  test "does not change the updater column when the values do not change" do
    @owner.config.set("key", "value", @owner)
    @owner.config.set("key", "value", @user)
    assert_equal @owner, @owner.configuration_entries.find_by(name: "key").updater
  end

  test "does not allow updater to be nil" do
    err = assert_raises ActiveRecord::RecordInvalid do
      @owner.config.set("key", "value", nil)
    end
    assert_match "Validation failed: Updater must exist", err.message
  end

  test "does not send instrumentation when the values do not change" do
    @owner.config.set("key", "value", @user)
    events = subscribe "config_entry.update"
    @owner.config.set("key", "value", @owner)
    assert_nil events.pop, "an event was not expected"
  end

  test "check value of a multi-state flag value" do
    key = "tri-state-bool"

    assert_nil @repo.config.raw(key)
    assert_nil @repo.config.get(key)

    val = "thingy"
    @repo.config.set(key, val, @user)
    assert_equal val, @repo.config.get(key)

    val = "again"
    @repo.config.set(key, val, @user)
    assert_equal val, @repo.config.get(key)

    @repo.config.set(key, "false", @user)
    assert_equal false, @repo.config.get(key)

    @repo.config.delete(key, @user)
    assert_nil @repo.config.get(key)
  end

  test "values cascade or override" do
    assert_nil GitHub.config.get("gkey")
    assert_nil @owner.config.get("okey")
    assert_nil @repo.config.get("key")

    gval = "globalval"
    oval = "ownerval"
    rval = "repoval"

    @repo.config.set  "key",  rval, @user
    @owner.config.set "okey", oval, @user
    GitHub.config.set "gkey", gval, @user

    assert_equal rval, @repo.config.get("key")

    assert_equal oval, @owner.config.get("okey")
    assert_equal oval, @repo.config.get("okey")

    assert_equal gval, GitHub.config.get("gkey")
    assert_equal gval, @owner.config.get("gkey")
    assert_equal gval, @repo.config.get("gkey")

    @repo.config.set  "okey", rval, @user
    assert_equal rval, @repo.config.get("okey")

    @owner.config.set! "okey", oval, @user
    @repo.config.reset
    assert_equal oval, @repo.config.get("okey")

    @owner.config.set "gkey", oval, @user
    @repo.config.reset
    assert_equal oval, @owner.config.get("gkey")
    assert_equal oval, @repo.config.get("gkey")

    GitHub.config.set! "gkey", gval, @user
    @repo.config.reset
    @owner.config.reset
    assert_equal gval,  @owner.config.get("gkey")
    assert_equal gval,  @repo.config.get("gkey")
  end

  test "cascading with deleting keys" do
    oval = "ownerval"
    rval = "repoval"

    assert_nil @owner.config.get("key")
    assert_nil @repo.config.get("key")

    @owner.config.set "key", oval, @user
    @repo.config.reset
    assert_equal oval, @owner.config.get("key")
    assert_equal oval, @repo.config.get("key")

    @repo.config.set "key", rval, @user
    assert_equal oval, @owner.config.get("key")
    assert_equal rval, @repo.config.get("key")

    @repo.config.delete "key"
    assert_equal oval, @owner.config.get("key")
    assert_equal oval, @repo.config.get("key")

    @owner.config.delete "key"
    @repo.config.reset
    assert_nil @owner.config.get("key")
    assert_nil @repo.config.get("key")
  end

  test "returns a full hash of config" do
    expected = {}
    assert_equal expected, @repo.config.to_hash

    gval = "globalval"
    oval = "ownerval"
    rval = "repoval"

    GitHub.config.set "gkey", gval, @user
    @owner.config.set "okey", oval, @user
    @repo.config.set  "key",  rval, @user

    expected = {
      "gkey" => gval,
      "okey" => oval,
      "key"  => rval,
    }

    assert_equal expected, @repo.config.to_hash

    newval = "thing"
    @repo.config.set "gkey", newval, @user
    expected["gkey"] = newval

    assert_equal expected, @repo.config.to_hash
  end

  test "final? returns true on final settings from anywhere" do
    gval = "globalval"
    oval = "ownerval"
    rval = "repoval"

    GitHub.config.set "gkey", gval, @user
    @owner.config.set! "okey", oval, @user
    @repo.config.set!  "key",  rval, @user

    refute @repo.config.final?("gkey")
    assert @repo.config.final?("okey")
    assert @repo.config.final?("key")
  end

  test "inherited? returns true if the key was set on another object" do
    gval = "globalval"
    oval = "ownerval"
    rval = "repoval"

    GitHub.config.set "gkey", gval, @user
    @owner.config.set "okey", oval, @user
    @repo.config.set  "key",  rval, @user

    refute @repo.config.inherited?("key")
    assert @repo.config.inherited?("gkey")
    assert @repo.config.inherited?("okey")
  end

  test "inherited? returns false when there is no config set" do
    refute @repo.config.inherited?("key")
    refute @repo.config.inherited?("gkey")
    refute @repo.config.inherited?("okey")
  end

  test "local? returns true if the key was set on this object" do
    gval = "globalval"
    oval = "ownerval"
    rval = "repoval"

    GitHub.config.set "gkey", gval, @user
    @owner.config.set "okey", oval, @user
    @repo.config.set  "key",  rval, @user

    assert @repo.config.local?("key")
    refute @repo.config.local?("gkey")
    refute @repo.config.local?("okey")
  end

  test "local? returns false when there is no config set" do
    refute @repo.config.local?("key")
    refute @repo.config.local?("gkey")
    refute @repo.config.local?("okey")
  end

  test "writable? returns true when values are locally set or not policy" do
    gval = "globalval"
    rval = "repoval"

    GitHub.config.set   "gkey", gval, @user
    @repo.config.set!   "key",  rval, @user

    assert @repo.config.writable?("key")
    assert @repo.config.writable?("gkey")
  end

  test "writable? returns false when there's an inherited final setting" do
    gval = "globalval"
    GitHub.config.set!   "gkey", gval, @user

    refute @repo.config.writable?("gkey")
  end

  test "source gives you the object the key is set" do
    gval = "globalval"
    oval = "ownerval"
    rval = "repoval"

    GitHub.config.set "gkey", gval, @user
    @owner.config.set "okey", oval, @user
    @repo.config.set  "key",  rval, @user

    assert_equal @repo,  @repo.config.source("key")
    assert_equal GitHub, @repo.config.source("gkey")
    assert_equal @owner, @repo.config.source("okey")
  end

  test "instrumenting configuration creation" do
    events = subscribe "config_entry.create"

    key = "somenewkey"
    val = "someval"
    @repo.config.set key, val, @user

    expected_payload = {
      name: key,
      value: val,
      repo: @repo.name_with_owner,
      repo_id: @repo.id,
      public_repo: @repo.public?,
      actor: @user.login,
      actor_id: @user.id,
      target_id: @repo.id,
      target_type: "Repository",
      final: false,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload

    @repo.config.set key, "somethingelse", @user

    assert_nil events.pop, "an event was not expected"
  end

  test "instrumenting configuration updating" do
    events = subscribe "config_entry.update"

    key = "somekey"
    val = "someval"
    @repo.config.set key, val, @user

    assert_nil events.pop, "an event was not expected"

    newval = "somenewval"
    @repo.config.set key, newval, @user

    expected_payload = {
      name: key,
      value: newval,
      old_value: val,
      repo: @repo.name_with_owner,
      repo_id: @repo.id,
      public_repo: @repo.public?,
      actor: @user.login,
      actor_id: @user.id,
      target_id: @repo.id,
      target_type: "Repository",
      final: false,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instrumenting configuration removal" do
    events = subscribe "config_entry.destroy"

    key = "somekey"
    val = "someval"
    @repo.config.set key, val, @user

    assert_nil events.pop, "an event was not expected"

    @repo.config.delete key, @owner

    expected_payload = {
      name: key,
      value: val,
      repo: @repo.name_with_owner,
      repo_id: @repo.id,
      public_repo: @repo.public?,
      actor: @owner.login,
      actor_id: @owner.id,
      target_id: @repo.id,
      target_type: "Repository",
      final: false,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instrumenting account-level config" do
    events = subscribe "config_entry.create"

    key = "somekey"
    val = "someval"
    @owner.config.set key, val, @user

    expected_payload = {
      name: key,
      value: val,
      user: @owner.login,
      user_id: @owner.id,
      actor: @user.login,
      actor_id: @user.id,
      target_id: @owner.id,
      target_type: "User",
      final: false,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload

    key = "otherkey"
    val = "otherval"
    @org.config.set key, val, @owner

    expected_payload = {
      name: key,
      value: val,
      org: @org.login,
      org_id: @org.id,
      actor: @owner.login,
      actor_id: @owner.id,
      target_id: @org.id,
      target_type: "User",
      final: false,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instrumenting global config" do
    events = subscribe "config_entry.create"

    key = "somekey"
    val = "someval"
    GitHub.config.set key, val, @user

    expected_payload = {
      name: key,
      value: val,
      actor: @user.login,
      actor_id: @user.id,
      target_id: 0,
      target_type: "global",
      final: false,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "git lfs access for user without git lfs enabled " do
    GitHub.git_lfs_enabled = false
    refute @owner.git_lfs_enabled?

    @owner.enable_git_lfs(@owner)
    assert @owner.git_lfs_enabled?

    @owner.disable_git_lfs(@owner)
    refute @owner.git_lfs_enabled?

    @owner.enable_git_lfs(@owner)
    assert @owner.git_lfs_enabled?
  end

  test "git lfs access for user with git lfs enabled " do
    GitHub.git_lfs_enabled = true
    assert @owner.git_lfs_enabled?, "failed with nil config"

    @owner.config.enable("git-lfs", @owner)
    assert @owner.git_lfs_enabled?, "failed with legacy true config"

    @owner.disable_git_lfs(@owner)
    refute @owner.git_lfs_enabled?, "failed after #disable_git_lfs"

    @owner.enable_git_lfs(@owner)
    assert @owner.git_lfs_enabled?, "failed after #enable_git_lfs"
    assert_nil @owner.config.get("git-lfs"), "old value stuck around"
  end

  test "git lfs access for repository without git lfs enabled " do
    GitHub.git_lfs_enabled = false
    refute @repo.git_lfs_enabled?

    @repo.enable_git_lfs(@owner)
    assert @repo.git_lfs_enabled?

    @repo.disable_git_lfs(@owner)
    refute @repo.git_lfs_enabled?

    @repo.enable_git_lfs(@owner)
    assert @repo.git_lfs_enabled?
  end

  test "git lfs access for repository with git lfs enabled " do
    GitHub.git_lfs_enabled = true
    assert @repo.git_lfs_enabled?, "failed with nil config"

    @repo.config.enable("git-lfs", @owner)
    assert @repo.git_lfs_enabled?, "failed with legacy true config"

    @repo.disable_git_lfs(@owner)
    refute @repo.git_lfs_enabled?, "failed after #disable_git_lfs"

    @repo.enable_git_lfs(@owner)
    assert @repo.git_lfs_enabled?, "failed after #enable_git_lfs"
    assert_nil @repo.config.get("git-lfs"), "old value stuck around"
  end

  test "enforce length limit for key" do
    key = "long" * 21
    val = "short"

    assert_nil GitHub.config.get(key), "key already exists"

    assert_raises ActiveRecord::RecordInvalid do
      GitHub.config.set key, val, @user
    end
  end

  test "enforce length limit for value" do
    key = "short"
    val = "long" * 64

    assert_nil GitHub.config.get(key), "key already exists"

    assert_raises ActiveRecord::RecordInvalid do
      GitHub.config.set key, val, @user
    end
  end
end

class ConfigurationSetErrors < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @user = create(:user)
  end

  setup do
    key_entry_attributes = {
      target_id: @repo.id,
      target_type: "Repository",
      updater_id: @user.id,
      name: "key",
      value: "someval",
      final: false,
    }

    Configuration::Entry.create!(key_entry_attributes)
    new_key_entry = Configuration::Entry.new(key_entry_attributes)
    Configuration::Entry.const_get(:ActiveRecord_AssociationRelation).any_instance.stubs(:first_or_initialize).with(name: "key").returns(new_key_entry)
    Configuration.any_instance.stubs(:find_or_initialize_entry_by_name).with("key").returns(new_key_entry)

    bool_entry_attributes = {
      target_id: @repo.id,
      target_type: "Repository",
      updater_id: @user.id,
      name: "bool",
      value: "false",
      final: false,
    }

    Configuration::Entry.create!(bool_entry_attributes)
    new_bool_entry = Configuration::Entry.new(bool_entry_attributes)
    Configuration::Entry.const_get(:ActiveRecord_AssociationRelation).any_instance.stubs(:first_or_initialize).with(name: "bool").returns(new_bool_entry)
    Configuration.any_instance.stubs(:find_or_initialize_entry_by_name).with("bool").returns(new_bool_entry)
  end

  context "#set encounters an ActiveRecord::RecordNotUnique error" do
    test "#set returns false in the event that a value equal to the persisted record is attempting to be set" do
      assert_nothing_raised do
        assert_equal false, @repo.config.set("key", "someval", @user)
      end
    end

    test "#set raises a Configration::ConflictingRecordError in the event that a value not equal to the persisted record is attempting to be set" do
      error = assert_raises Configuration::ConflictingRecordError do
        @repo.config.set "key", "another_value", @user
      end

      assert_equal error.setting_name, "key"
    end

    test "#set returns false in the event that a disabled config collides with an equivalent disabled config" do
      assert_nothing_raised do
        assert_equal false, @repo.config.disable("bool", @user)
      end
    end
  end
end
