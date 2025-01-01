# typed: true
# frozen_string_literal: true

require "test_helper"

class AuditLogEntryTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @staff = create :staff_admin_user
    @authenticated_device = create(:authenticated_device, user: @user)
    User.create_ghost
  end

  setup do
    @time = Time.zone.parse "2013-12-10 03:47:48 -0700"
    # Recreate the string because timezones
    @timestamp = @time.strftime "%Y-%m-%d %H:%M:%S %z"

    @location = {
      region_name: "Wyoming",
      city: "Nowhere",
      country_name: "United States",
      country_code: "US",
    }

    @raw_entry = {
      :@timestamp => (@time.to_i * 1000),
      :action => "user.add_email",
      :actor => @user.login,
      :actor_id => @user.id,
      :user => @user.login,
      :user_id => @user.id,
      :created_at => (@time.to_i * 1000),
      :device_cookie => @authenticated_device.device_id,
      :data => {
        timing: "It's about time!",
        email: "rawr@bear.com",
        console_host: "github-staff3-cp1",
        active: false,
        skipped: true,
        marketplace_listing_id: 21,
      },
    }
    @raw_ip_entry = @raw_entry.merge actor_ip: "1.1.1.1"
    @log_entry = AuditLogEntry.new_from_hash @raw_entry
    @ip_entry = AuditLogEntry.new_from_hash @raw_ip_entry
    @log_entries = AuditLogEntry.new_from_array [@raw_entry, @raw_ip_entry]

    raw_create_entry = @raw_ip_entry.merge action: "user.create"
    @create_entry = AuditLogEntry.new_from_hash raw_create_entry

    raw_create_entry_staff = raw_create_entry.merge actor: @staff.login, actor_id: @staff.id
    @create_entry_staff = AuditLogEntry.new_from_hash raw_create_entry_staff

    fake_login = @raw_entry.merge action: "staff.fake_login"
    @fake_login_entry = AuditLogEntry.new_from_hash fake_login

    impersonated_action = @raw_entry.merge session_impersonated: true
    @impersonated_entry = AuditLogEntry.new_from_hash impersonated_action

    oauth_update = @raw_entry.merge action: "oauth_access.update"
    @oauth_update_entry = AuditLogEntry.new_from_hash oauth_update

    staff_action = @raw_entry.merge action: "staff.action", staff_actor: @staff.to_s, staff_actor_id: @staff.id
    @staff_action_entry = AuditLogEntry.new_from_hash staff_action

    recreate_action = @raw_entry.merge action: "user.recreate"
    @recreate_action_entry = AuditLogEntry.new_from_hash recreate_action

    GitHub::Location.stubs(:look_up).with("1.1.1.1").returns(@location)
    GitHub.audit.stubs(:search).returns([@raw_entry, @raw_ip_entry])
  end

  context ".keys" do
    test "returns a Set" do
      assert AuditLogEntry.keys.is_a?(Set)
    end

    test "returns keys as symbols" do
      assert AuditLogEntry.keys.include?(:action)
    end
  end

  context "allowed_key?" do
    test "blocked_user is an allowed attribute" do
      assert AuditLogEntry.allowed_key?(:blocked_user), "expected blocked_user to be an allowed key"
      assert AuditLogEntry.allowed_key_for_self?(:blocked_user), "expected blocked_user to be an allowed key"
      refute AuditLogEntry.denied_key?(:blocked_user), "blocked_user should not be a denied key"
    end

    test "deploy_key_fingerprint is an allowed attribute" do
      assert AuditLogEntry.allowed_key?(:deploy_key_fingerprint), "expected deploy_key_fingerprint to be an allowed key"
      assert AuditLogEntry.allowed_key_for_self?(:deploy_key_fingerprint), "expected deploy_key_fingerprint to be an allowed key"
      refute AuditLogEntry.denied_key?(:deploy_key_fingerprint), "deploy_key_fingerprint should not be a denied key"
    end
  end

  context ".new_from_hash" do
    test "generates an AuditLogEntry from a hash" do
      assert @log_entry.is_a?(AuditLogEntry)
    end

    test "assigns attributes from the hash" do
      assert_equal @user.login, @log_entry.instance_variable_get(:@actor)
    end

    test "assigns attributes from hash[:data]" do
      assert_equal @raw_entry[:data][:marketplace_listing_id], @log_entry.marketplace_listing_id
    end
  end

  context ".new_from_array" do
    test "returns an Array" do
      assert @log_entries.is_a?(Array)
    end

    test "returned Array contains AuditLogEntries" do
      assert @log_entries.all? { |value| value.is_a?(AuditLogEntry) }
    end

    test "returned Array rejects hidden entries" do
      @hidden_entry = {
        action: "user.add_email",
        actor: @user.login,
        actor_id: @user.id,
        user: @user.login,
        user_id: @user.id,
        created_at: (@time.to_i * 1000),
        data: {
          "_invalid" => true,
        },
      }

      log_entries = AuditLogEntry.new_from_array [@raw_entry, @raw_ip_entry, @hidden_entry]

      assert_equal 2, log_entries.length
    end
  end

  context "#impersonated?" do
    test "returns true if session was impersonated" do
      assert @impersonated_entry.impersonated?
    end

    test "returns false if session was not impersonated" do
      refute @log_entry.impersonated?
    end
  end

  context "#actor" do
    test "returns a User" do
      assert_equal @user, @log_entry.actor
    end
  end

  context "#safe_actor" do
    test "returns actor if found" do
      assert @log_entry.actor?
      assert @log_entry.actor_present?
      refute @log_entry.actor_deleted?
      refute @log_entry.actor_missing?
      assert_equal @log_entry.actor, @log_entry.safe_actor
    end

    test "returns ghost login if actor is blank string" do
      entry = AuditLogEntry.new_from_hash({
        actor: "",
      })

      assert_equal "ghost", entry.safe_actor_login
    end

    test "returns actor's actual login if a ghost user" do
      deleted_actor = create(:user, login: "deleted-user")

      @entry = AuditLogEntry.new_from_hash({
        action: "user.login",
        actor: deleted_actor.login,
        actor_id: deleted_actor.id,
      })

      deleted_actor.destroy

      refute_predicate @entry, :actor?
      refute_predicate @entry, :actor_present?
      assert_predicate @entry, :actor_missing?
      assert_predicate @entry, :actor_deleted?
      assert_equal User.ghost, @entry.safe_actor
      assert_equal deleted_actor.login, @entry.safe_actor_login
    end

    test "returns ghost user if actor is present" do
      @entry = AuditLogEntry.new_from_hash(action: "user.login")

      assert_nil @entry.actor
      refute @entry.actor?
      refute @entry.actor_present?
      assert @entry.actor_missing?
      assert @entry.actor_deleted?
      assert_equal User.ghost, @entry.safe_actor
      assert_equal User.ghost.login, @entry.safe_actor_login
    end
  end

  context "#user" do
    test "returns a User" do
      assert_equal @user, @log_entry.user
    end
  end

  context "#safe_user" do
    test "returns user if found" do
      refute_nil @log_entry.user
      assert_equal @log_entry.user, @log_entry.safe_user
    end

    test "returns ghost user if user not found" do
      @entry = AuditLogEntry.new_from_hash user_id: nil
      assert_nil @entry.user
      assert_equal User.ghost, @entry.safe_user
    end
  end

  context "#to_hash" do
    test "returns a hash" do
      expected = @raw_entry.slice(*AuditLogEntry.keys)
      AuditLogEntry.keys.each do |key|
        expected[key] ||= @log_entry.send(key)
      end

      actual = @log_entry.to_hash

      assert_equal expected, actual
    end
  end

  context "#metadata" do
    test "returns a Hash" do
      assert @log_entry.metadata.is_a?(Hash)
    end

    test "returns a hash with denied keys removed" do
      assert !@log_entry.metadata.has_key?(:timing)
    end

    test "returns a hash with nil values removed" do
      assert !@log_entry.metadata.has_key?(:oauth_app_id)
    end

    test "returns a hash with boolean values present" do
      assert @log_entry.metadata.has_key?(:active)
      assert @log_entry.metadata.has_key?(:skipped)
    end

    test "includes the device cookie value" do
      assert @log_entry.metadata.has_key?(:device_cookie)
    end

    test "created_at is returned in UTC" do
      zone = ActiveSupport::TimeZone.new("UTC")
      assert_equal @timestamp, @log_entry.metadata(time_zone: zone)[:created_at]
    end

    test "created_at is returned in configured time zone" do
      zone = ActiveSupport::TimeZone.new("Madrid")
      Time.stubs(:zone).returns(zone)
      assert_equal @time.in_time_zone(zone).strftime("%Y-%m-%d %H:%M:%S %z"), @log_entry.metadata[:created_at]
    end

    test "created_at is not cached if time zone changes" do
      custom_zone = ActiveSupport::TimeZone.new("Madrid")
      assert_equal @time.in_time_zone(custom_zone).strftime("%Y-%m-%d %H:%M:%S %z"), @log_entry.metadata(time_zone: custom_zone)[:created_at]
      utc = ActiveSupport::TimeZone.new("UTC")
      assert_equal @timestamp, @log_entry.metadata(time_zone: utc)[:created_at]
    end

    test "@timestamp is returned in UTC" do
      zone = ActiveSupport::TimeZone.new("UTC")
      assert_equal @timestamp, @log_entry.metadata(time_zone: zone)[:@timestamp]
    end

    test "@timestamp is returned in configured time zone" do
      zone = ActiveSupport::TimeZone.new("Madrid")
      Time.stubs(:zone).returns(zone)
      assert_equal @time.in_time_zone(zone).strftime("%Y-%m-%d %H:%M:%S %z"), @log_entry.metadata[:@timestamp]
    end

    test "@timestamp is not cached if time zone changes" do
      custom_zone = ActiveSupport::TimeZone.new("Madrid")
      assert_equal @time.in_time_zone(custom_zone).strftime("%Y-%m-%d %H:%M:%S %z"), @log_entry.metadata(time_zone: custom_zone)[:@timestamp]
      utc = ActiveSupport::TimeZone.new("UTC")
      assert_equal @timestamp, @log_entry.metadata(time_zone: utc)[:@timestamp]
    end

    test "marked_invalid_at is returned in UTC" do
      @invalid_entry = {
        action: "user.add_email",
        actor: @user.login,
        actor_id: @user.id,
        user: @user.login,
        user_id: @user.id,
        created_at: (@time.to_i * 1000),
        data: {
          "_invalid" => true,
          "_invalid_at" => (@time.to_i * 1000),
        },
      }

      entry = AuditLogEntry.new_from_hash @invalid_entry
      zone = ActiveSupport::TimeZone.new("UTC")
      assert_equal @time.in_time_zone(zone).strftime("%Y-%m-%d %H:%M:%S %z"), entry.metadata(time_zone: zone)[:_invalid_at]
    end

    test "marked_invalid_at is configured time zone" do
      zone = ActiveSupport::TimeZone.new("Madrid")
      Time.stubs(:zone).returns(zone)

      @invalid_entry = {
        action: "user.add_email",
        actor: @user.login,
        actor_id: @user.id,
        user: @user.login,
        user_id: @user.id,
        created_at: (@time.to_i * 1000),
        data: {
          "_invalid" => true,
          "_invalid_at" => (@time.to_i * 1000),
        },
      }

      entry = AuditLogEntry.new_from_hash @invalid_entry
      assert_equal @time.in_time_zone(zone).strftime("%Y-%m-%d %H:%M:%S %z"), entry.metadata[:_invalid_at]
    end
  end

  context "#sanitized_metadata" do
    test "returns a Hash" do
      assert @log_entry.sanitized_metadata.is_a?(Hash)
    end

    test "returns a hash with only allowed keys" do
      refute @log_entry.sanitized_metadata.key?(:actor_id)
      refute @log_entry.sanitized_metadata.key?(:console_host)
      refute @staff_action_entry.sanitized_metadata.key?(:staff_actor)
      refute @staff_action_entry.sanitized_metadata.key?(:staff_actor_id)
    end

    test "extra keys are shown if actor is staff" do
      assert @staff_action_entry.sanitized_metadata(@staff).key?(:staff_actor)
      assert @staff_action_entry.sanitized_metadata(@staff).key?(:staff_actor_id)
    end

    test "extra keys are shown if actor is current_user" do
      assert @ip_entry.sanitized_metadata(@user).key?(:actor_ip)
    end

    test "extra keys are not shown if current_user isn't given" do
      refute @ip_entry.sanitized_metadata.key?(:actor_ip)
    end

    test "extra keys are not shown if actor isn't current_user" do
      other_user = create(:user)
      refute @ip_entry.sanitized_metadata(other_user).key?(:actor_ip)
    end

    test "extra keys are not shown if action is repo.add_member" do
      @entry = AuditLogEntry.new_from_hash({
        action: "repo.add_member",
        actor: @user.login,
        actor_id: @user.id,
        actor_ip: "1.1.1.1",
        user: "dinahshi",
        user_id: 12345,
        created_at: (@time.to_i * 1000),
      })

      refute @entry.sanitized_metadata(@user).key?(:actor_ip)
      refute @entry.sanitized_metadata(@user).key?(:actor_location)
    end
  end

  context "Internal IPs" do
    test "10.* address returns true for internal ip on dotcom and false on enterprise" do
      entry = AuditLogEntry.new_from_hash({
        action: "repo.create",
        actor: @user.login,
        actor_id: @user.id,
        actor_ip: "10.125.1.12",
        actor_location: "Somewhere in the world",
        user: @user.login,
        user_id: @user.id,
        created_at: (@time.to_i * 1000),
      })

      if GitHub.enterprise?
        # always returns false for enterprise so we don't mask any internal IPs
        refute entry.internal_ip?
      else
        assert entry.internal_ip?
      end
    end

    test "212.* address returns false for internal ip on dotcom and enterprise" do
      entry = AuditLogEntry.new_from_hash({
        action: "repo.create",
        actor: @user.login,
        actor_id: @user.id,
        actor_ip: "212.111.32.123",
        actor_location: "Somewhere in the world",
        user: @user.login,
        user_id: @user.id,
        created_at: (@time.to_i * 1000),
      })

      # This should be false for dotcom and enterprise
      refute entry.internal_ip?
    end
  end

  test "#user_metadata removes actor_ip and actor_location if action is repo.add_member" do
    @entry = AuditLogEntry.new_from_hash({
      action: "repo.add_member",
      actor: @user.login,
      actor_id: @user.id,
      actor_ip: "1.1.1.1",
      actor_location: "Somewhere in the world",
      user: @user.login,
      user_id: @user.id,
      created_at: (@time.to_i * 1000),
    })

    refute @entry.user_metadata.key?(:actor_ip)
    refute @entry.user_metadata.key?(:actor_location)
  end

  test "#user_metadata does not remove actor_ip and actor_location if action is not repo.add_member" do
    @entry = AuditLogEntry.new_from_hash({
      action: "user.add_email",
      actor: @user.login,
      actor_id: @user.id,
      actor_ip: "1.1.1.1",
      actor_location: "Somewhere in the world",
      user: @user.login,
      user_id: @user.id,
      created_at: (@time.to_i * 1000),
    })

    assert @entry.user_metadata.key?(:actor_ip)
    assert @entry.user_metadata.key?(:actor_location)
  end

  test "#display_actor_location? returns false when action is repo.add_member" do
    @entry = AuditLogEntry.new_from_hash({
      action: "repo.add_member",
      actor: @user.login,
      actor_id: @user.id,
      actor_ip: "1.1.1.1",
      actor_location: "Somewhere in the world",
      user: @user.login,
      user_id: @user.id,
      created_at: (@time.to_i * 1000),
    })

    refute @entry.display_actor_location?(@user)
  end

  context "#pretty_metadata" do
    test "returns well-formatted JSON" do
      pretty_json = %{
{
  "action": "user.add_email",
  "active": false,
  "actor": "#{@user.login}",
  "created_at": "#{@timestamp}",
  "user": "#{@user.login}"
}
        }.strip
      assert_equal pretty_json, @log_entry.pretty_metadata
    end
  end

  context "#created_at" do
    test "returns a ruby Time" do
      assert @log_entry.created_at.is_a?(Time)
    end
  end

  context "#created_at_timestamp" do
    test "returns a timestamp string" do
      assert_equal @timestamp, @log_entry.created_at_timestamp
    end
  end

  context "#own_entry?" do
    test "knows if entry is self targeted" do
      entry = AuditLogEntry.new_from_hash(actor_id: 1, user_id: 1)
      assert entry.own_entry?

      entry = AuditLogEntry.new_from_hash(actor_id: 2, user_id: 1)
      refute entry.own_entry?
    end
  end

  context "location" do
    test "returns raw location data if present" do
      actor_location = {
        "country_code" => "US",
      }
      entry = AuditLogEntry.new_from_hash(actor_location: actor_location)
      assert entry.actor_location?
      assert_equal actor_location, entry.location
    end

    test "returns nothing if local ip or no cached data" do
      entry = AuditLogEntry.new_from_hash(actor_ip: "127.0.0.1")
      refute entry.external_ip?
      refute entry.actor_location?
      assert_nil entry.location
    end

    test "returns nothing if a local ip" do
      entry = AuditLogEntry.new_from_hash(actor_ip: "127.0.0.1")
      refute entry.external_ip?
      assert_nil entry.location
    end

    test "knows if an ip is an external ip" do
      entry = AuditLogEntry.new_from_hash(actor_ip: "1.1.1.1")
      assert entry.external_ip?

      entry = AuditLogEntry.new_from_hash(actor_ip: "127.0.0.1")
      refute entry.external_ip?
    end

    test "returns country_name from cache" do
      entry = AuditLogEntry.new_from_hash(actor_location: { "country_name" => "United States", "country_code" => "US" })
      assert entry.actor_location?
      assert_equal "United States", entry.country
    end

    test "returns country_name from geo lookup" do
      entry = AuditLogEntry.new_from_hash(actor_ip: "1.1.1.1")
      refute entry.actor_location?
      assert_equal "United States", entry.country
    end

    test "returns country_code from cache" do
      entry = AuditLogEntry.new_from_hash(actor_location: { "country_code" => "US" })
      assert entry.actor_location?
      assert_equal "US", entry.country_code
    end

    test "returns country_code from geo lookup" do
      entry = AuditLogEntry.new_from_hash(actor_ip: "1.1.1.1")
      refute entry.actor_location?
      assert_equal "US", entry.country_code
    end

    # This test is disabled because we're stubbing out the results. If GeoIP
    # were to provide us with proper (consistant) test data in the future, we
    # could kill that icky stub.  But as things stand, we have to stub or we
    # might get different results in different environments.
    #
    # test "returns a location hash if we have an IP" do
    #   assert_equal @location, @ip_entry.send(:location)
    # end
  end

  context "#show_country?" do
    test "Action triggered by non-staff returns true" do
      assert_equal true, @log_entry.show_country?
    end

    test "Action triggered by staff returns false", skip_enterprise: true do
      GitHub.stubs(:guard_audit_log_staff_actor).returns(true)
      @staff_action_entry

      assert_equal false, @staff_action_entry.show_country?
    end

    test "Action triggered by non-staff and in Audit::ActionsHideCountry::ACTIONS returns false", skip_enterprise: true do
      GitHub.stubs(:guard_audit_log_staff_actor).returns(true)
      log_entry = AuditLogEntry.new_from_hash(action: "repo.self_hosted_runner_updated")

      assert_equal false, log_entry.show_country?
    end
  end

  context "#geolocation" do
    test "returns nothing if we don't have an IP" do
      assert_nil @log_entry.geolocation
    end

    test "returns a location string if we have an IP" do
      assert_equal "Nowhere, Wyoming, United States", @ip_entry.geolocation
    end
  end

  context "#public_repo?" do
    test "returns true if public_repo is true or 'true'" do
      [true, "true"].each do |value|
        @log_entry.public_repo = value
        assert_equal true, @log_entry.public_repo?
      end
    end

    test "returns false if public_repo is nil or false" do
      [nil, false].each do |value|
        @log_entry.public_repo = value
        assert_equal false, @log_entry.public_repo?
      end
    end
  end

  context "before_public_repo_cutoff?" do
    test "returns true if at_timestamp is before the cutoff" do
      @log_entry.stubs(:at_timestamp).returns(AuditLogEntry::PUBLIC_REPO_CUTOFF - 1)
      assert_equal true, @log_entry.before_public_repo_cutoff?
    end

    test "returns false if at_timestamp is equal to or after the cutoff" do
      [AuditLogEntry::PUBLIC_REPO_CUTOFF, AuditLogEntry::PUBLIC_REPO_CUTOFF + 1].each do |timestamp|
        @log_entry.stubs(:at_timestamp).returns(timestamp)
        assert_equal false, @log_entry.before_public_repo_cutoff?
      end
    end
  end

  context "ip_safe_action?" do
    test "returns true if the action is included in the list of actions" do
      Audit::ActionsIpSafe.stub_const(:ACTIONS, ["repo.create"]) do
        @log_entry.action = "repo.create"
        assert_equal true, @log_entry.ip_safe_action?
      end
    end

    test "returns false if the action is not included in the list of actions" do
      Audit::ActionsIpSafe.stub_const(:ACTIONS, ["repo.create"]) do
        @log_entry.action = "repo.destroy"
        assert_equal false, @log_entry.ip_safe_action?
      end
    end
  end

  context "#country" do
    test "returns nothing if we don't have an IP" do
      refute @log_entry.location?
      assert_nil @log_entry.country
    end

    test "returns a country string if we have an IP" do
      assert @ip_entry.location?
      assert_equal "United States", @ip_entry.country
    end
  end

  context ".for_users" do
    test "only returns entries that users can view" do
      assert_equal @log_entry.to_hash, AuditLogEntry.for_users([@raw_entry]).first.to_hash

      org_invite_member = @raw_entry.merge action: "org.invite_member"
      assert AuditLogEntry.for_users([org_invite_member]).empty?
    end
  end

  context "#hidden_from_users?" do
    test "entries in groups that aren't allowed are hidden" do
      assert @fake_login_entry.hidden_from_users?

      org_invite_member = @raw_entry.merge action: "org.invite_member"
      @org_invite_member_entry = AuditLogEntry.new_from_hash(org_invite_member)

      assert @org_invite_member_entry.hidden_from_users?
    end

    test "entries in allowed groups are shown" do
      refute @log_entry.hidden_from_users?

      org_add_member = @raw_entry.merge action: "org.add_member"
      @org_add_member_entry = AuditLogEntry.new_from_hash(org_add_member)

      refute @org_add_member_entry.hidden_from_users?
    end
  end

  context ".for_orgs" do
    test "only returns entries that organizations can view" do
      assert AuditLogEntry.for_orgs([@raw_entry]).blank?

      org_invite_member = @raw_entry.merge action: "org.invite_member"
      org_invite_member_entry = AuditLogEntry.new_from_hash(org_invite_member)
      for_orgs_result = AuditLogEntry.for_orgs([org_invite_member]).first
      assert_equal org_invite_member_entry.to_hash, for_orgs_result.to_hash
    end
  end

  context "#hidden_from_orgs?" do
    test "entries with denied actions are hidden" do
      assert @oauth_update_entry.hidden_from_orgs?
    end

    test "entries in groups that aren't allowed are hidden" do
      assert @fake_login_entry.hidden_from_orgs?
    end

    test "entries in allowed groups are shown" do
      org_invite_member = @raw_entry.merge action: "org.invite_member"
      @org_invite_member_entry = AuditLogEntry.new_from_hash(org_invite_member)

      refute @org_invite_member_entry.hidden_from_orgs?
    end
  end

  context ".for_businesses" do
    test "returns entries that businesses can view" do
      business_create = @raw_entry.merge action: "business.create"
      business_create_entry = AuditLogEntry.new_from_hash(business_create)
      for_businesses_result = AuditLogEntry.for_businesses([business_create]).first
      assert_equal business_create_entry.to_hash, for_businesses_result.to_hash
    end

    if GitHub.single_business_environment?
      test "does not return entries that are denied for businesses in Enterprise Server" do
        denied_action = "account.plan_change"
        user_login = @raw_entry.merge action: denied_action
        assert AuditLogEntry.for_businesses([user_login]).blank?
      end
    else
      test "does not return entries that are denied for businesses in Enterprise Cloud" do
        denied_action = "user.login"
        user_login = @raw_entry.merge action: denied_action
        assert AuditLogEntry.for_businesses([user_login]).blank?
      end
    end
  end

  context "#hidden_from_businesses?" do
    test "entries with denied actions are hidden" do
      assert @oauth_update_entry.hidden_from_businesses?
    end

    test "entries in groups that aren't allowed are hidden" do
      assert @fake_login_entry.hidden_from_businesses?
    end

    test "entries in allowed groups are shown" do
      add_organization = @raw_entry.merge action: "business.add_organization"
      add_organization_entry = AuditLogEntry.new_from_hash(add_organization)
      refute add_organization_entry.hidden_from_businesses?
    end
  end

  context "#icon" do
    test "returns a string pointing to an octicon" do
      assert_equal "mail", @log_entry.icon
    end
  end

  context "#title" do
    test "returns a string containing a user-friendly title" do
      assert_equal "rawr@bear.com", @log_entry.title(viewer: @user)
    end

    test "returns no title if it's missing an argument for the i18n string" do
      assert_equal "", @staff_action_entry.title(viewer: @user)
    end

    test "returns ip if actor is self" do
      assert_equal "Originated from 1.1.1.1", @create_entry.title(viewer: @user)
    end

    test "does not return ip if actor is someone else" do
      assert_equal "", @create_entry_staff.title(viewer: @user)
    end

    test "returns support text for recreate event" do
      assert_equal "GitHub Support recreated this account upon user request", @recreate_action_entry.title(viewer: @user)
    end
  end

  context "#project" do
    test "returns the project if we have a project_id" do
      project = create(:project)
      entry_hash = @raw_entry.merge project_id: project.id
      entry = AuditLogEntry.new_from_hash(entry_hash)
      assert_equal project, entry.project
    end

    test "returns the memex project if we have a project_id and project kind is MemexProject" do
      memex = create(:memex_project)
      entry_hash = @raw_entry.merge project_id: memex.id, data: { "project_kind" => "MemexProject" }
      entry = AuditLogEntry.new_from_hash(entry_hash)
      assert_equal memex, entry.project
    end

    test "returns the memex project if we have a memex_project_id" do
      memex = create(:memex_project)
      entry_hash = @raw_entry.merge data: { "memex_project_id" => memex.id }
      entry = AuditLogEntry.new_from_hash(entry_hash)
      assert_equal memex, entry.project
    end
  end

  context "#organization" do
    test "returns the organization if we have an org_id" do
      org = create(:organization)
      entry_hash = @raw_entry.merge org_id: org.id
      entry = AuditLogEntry.new_from_hash(entry_hash)

      assert_equal org, entry.org
    end

    test "returns nil if we don't have an org_id" do
      entry_hash = @raw_entry.merge org_id: nil
      entry = AuditLogEntry.new_from_hash(entry_hash)

      assert_nil entry.org
    end
  end

  context "#safe_organization_name" do
    test "returns the org's current name if org_id is present" do
      org = create :organization, name: "In-N-Out"
      entry_hash = @raw_entry.merge org_id: org.id
      entry = AuditLogEntry.new_from_hash(entry_hash)

      org.update_attribute(:login, "In-N-Out Burger")

      assert_equal "In-N-Out Burger", entry.safe_organization_name
    end

    test "returns the org name from the entry if org_id is nil" do
      entry_hash = @raw_entry.merge org_id: nil, org: "Airbnb"
      entry = AuditLogEntry.new_from_hash(entry_hash)

      assert_equal "Airbnb", entry.safe_organization_name
    end
  end

  context "#business" do
    test "returns the business if we have a business_id" do
      business = create :business
      entry_hash = @raw_entry.merge business_id: business.id
      entry = AuditLogEntry.new_from_hash(entry_hash)

      assert_equal business, entry.business
      assert entry.business?, "Expected business to exist"
    end

    test "returns nil if we don't have a business_id" do
      entry_hash = @raw_entry.merge business_id: nil
      entry = AuditLogEntry.new_from_hash(entry_hash)

      assert_nil entry.business
      refute entry.business?, "Expected business to not exist"
    end
  end

  context "#safe_business_name" do
    test "returns the business's current name if business_id is present" do
      business = create :business, name: "So much ACME"
      entry_hash = @raw_entry.merge business_id: business.id
      entry = AuditLogEntry.new_from_hash(entry_hash)
      business.update_attribute(:name, "So much ACME Inc")
      assert_equal "So much ACME Inc", entry.safe_business_name
    end

    test "returns the business name from the entry if business_id is nil" do
      entry_hash = @raw_entry.merge org_id: nil, business: "acme"
      entry = AuditLogEntry.new_from_hash(entry_hash)
      assert_equal "acme", entry.safe_business_name
    end
  end

  context "#performed_by_viewer?" do
    test "is true if the entry actor_id and viewer id are the same" do
      assert AuditLogEntry.new_from_hash(@raw_entry).performed_by_viewer?(@user)
    end

    test "is false otherwise" do
      refute AuditLogEntry.new_from_hash(@raw_entry).performed_by_viewer?(@staff)
      refute AuditLogEntry.new_from_hash(@raw_entry).performed_by_viewer?(nil)
    end
  end

  context "#performed_by_staff?" do
    # In GHES, there is no staff actor used for auditing purposes, the difference in implementation
    # is handled by the guard_audit_log_staff_actor? method and other methods that use it.
    if GitHub.guard_audit_log_staff_actor?
      test "is true if any staff actor keys are set" do
        assert_predicate AuditLogEntry.new_from_hash(@raw_entry.merge(staff_actor_id: 99)), :performed_by_staff?
        assert_predicate AuditLogEntry.new_from_hash(@raw_entry.merge(staff_actor: "staff")), :performed_by_staff?
      end

      test "is true if any actor keys are assigned the staff actor" do
        assert_predicate AuditLogEntry.new_from_hash(@raw_entry.merge(actor_id: User.staff_user.id)), :performed_by_staff?
        assert_predicate AuditLogEntry.new_from_hash(@raw_entry.merge(actor: User.staff_user.login)), :performed_by_staff?
      end
    else # guard_audit_log_staff_actor? is false
      test "is always false" do
        refute_predicate AuditLogEntry.new_from_hash(@raw_entry.merge(staff_actor_id: 99)), :performed_by_staff?
        refute_predicate AuditLogEntry.new_from_hash(@raw_entry.merge(staff_actor: "staff")), :performed_by_staff?
      end
    end
  end

  context "#members_can_create_repositories_visibility" do
    [
      [Configurable::MembersCanCreateRepositories::PUBLIC, "only private and internal"],
      [Configurable::MembersCanCreateRepositories::PRIVATE, "only public and internal"],
      [Configurable::MembersCanCreateRepositories::INTERNAL, "only public and private"],
      [Configurable::MembersCanCreateRepositories::PUBLIC_INTERNAL, "only private"],
      [Configurable::MembersCanCreateRepositories::PRIVATE_INTERNAL, "only public"],
      [Configurable::MembersCanCreateRepositories::PUBLIC_PRIVATE, "only internal"],
      ["any other value", "public, private, and internal"],
    ].each do |value, expected_return_value|
      test "returns the correct value for #{value}" do
        assert_equal \
          expected_return_value,
          @log_entry.members_can_create_repositories_visibility(value)
      end
    end
  end
end
