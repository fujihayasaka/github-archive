# typed: false
# frozen_string_literal: true

require "test_helper"

class PrimaryAvatarTest < GitHub::TestCase
  include CdnTestHelper
  include AvatarHelpers
  include GitHub::LoggerHelper

  fixtures do
    @owner = create :user, login: "owner"
    @newb = create :user, login: "newb"
    @org = create :organization, login: "org", admin: @owner
    @avatar1 = create_avatar_for @owner
    @avatar2 = create_avatar_for @owner
    @org_avatar1 = create_avatar_for @org
    @org_avatar2 = create_avatar_for @org
    PrimaryAvatar.set @avatar2, @owner
    PrimaryAvatar.set @org_avatar1, @owner
    on_multi_tenant_enterprise do
      @multi_tenant_owner = create :emu
      @multi_tenant_business = @multi_tenant_owner.enterprise_managed_business
      @integration = create(:integration, name: "simple-ci", default_permissions: { "metadata" => :read })
      @bot = @integration.bot
    end
  end

  setup do
    @old_avatar_url = GitHub.alambic_avatar_url
  end

  teardown do
    GitHub.alambic_next_avatar_version = nil
    GitHub.alambic_next_browser_avatar_version = nil
    GitHub.alambic_next_avatar_chance = nil
    GitHub.alambic_avatar_url = @old_avatar_url
    GitHub.flipper[:authenticated_avatars].disable
  end

  context "(Avatar::Shared)" do
    test "internal uri template" do
      av = PrimaryAvatar.get @owner
      av.alambic_size_filter = 2 # ignored
      url, rawquery = av.uri_template.split("?", 2)
      query = Rack::Utils.parse_query(rawquery)
      assert_equal "media:/#{GitHub.alambic_path_prefix}/#{av.avatar_oid}", url
      assert_equal "{size}", query["s"]
      assert_equal "png", query["filter[image.encode]"]
      assert_equal "0,0,5,5", query["filter[image.crop]"]
      assert_equal "image/png", query["type"]
      assert_equal av.updated_at.to_i.to_s, query["last_mod"]
      assert_equal 5, query.size
    end

    test "internal uri template for original image" do
      av = PrimaryAvatar.get @owner
      av.alambic_use_original_filter = true
      url, rawquery = av.uri_template.split("?", 2)
      query = Rack::Utils.parse_query(rawquery)
      assert_equal "media:/#{GitHub.alambic_path_prefix}/#{av.avatar_oid}", url
      assert_equal "{size}", query["s"]
      assert_equal "png", query["filter[image.encode]"]
      assert_equal "image/png", query["type"]
      assert_equal av.updated_at.to_i.to_s, query["last_mod"]
      assert_equal 4, query.size
    end

    test "primary avatar png encoding" do
      av = PrimaryAvatar.get @owner
      av.avatar_id = Avatar::Shared::EARLIEST_FILTERED_ID - 1
      assert av.encode_to_png?

      av.avatar_id = Avatar::Shared::EARLIEST_FILTERED_ID
      refute av.encode_to_png?
    end

    test "internal uri template without encoding" do
      av = PrimaryAvatar.get @owner
      av.stubs(encode_to_png?: false)

      url, rawquery = av.uri_template.split("?", 2)
      query = Rack::Utils.parse_query(rawquery)
      assert_equal "media:/#{GitHub.alambic_path_prefix}/#{av.avatar_oid}", url
      assert_equal "{size}", query["s"]
      assert_equal "0,0,5,5", query["filter[image.crop]"]
      assert_equal "image/png", query["type"]
      assert_equal av.updated_at.to_i.to_s, query["last_mod"]
      assert_equal 4, query.size
    end

    test "image filter" do
      av = PrimaryAvatar.get @owner
      assert filter = av.alambic_image_filter
      assert_equal "0,0,5,5", filter[:params][:crop], filter.inspect
      assert_equal :png, filter[:params][:encode], filter.inspect
      assert_nil filter[:params][:resize], filter.inspect
    end

    test "image filter for original image" do
      av = PrimaryAvatar.get @owner
      av.alambic_use_original_filter = true
      assert filter = av.alambic_image_filter
      assert_equal :png, filter[:params][:encode], filter.inspect
      assert_nil filter[:params][:crop], filter.inspect
      assert_nil filter[:params][:resize], filter.inspect
    end

    test "image filter with resize" do
      av = PrimaryAvatar.get @owner
      av.alambic_size_filter = 4
      assert filter = av.alambic_image_filter
      assert_equal "0,0,5,5", filter[:params][:crop], filter.inspect
      assert_equal :png, filter[:params][:encode], filter.inspect
      assert_equal "4,4", filter[:params][:resize], filter.inspect
    end

    test "image filter without encoding" do
      av = PrimaryAvatar.get @owner
      av.avatar_id = Avatar::Shared::EARLIEST_FILTERED_ID + 1
      assert filter = av.alambic_image_filter
      assert_equal "0,0,5,5", filter[:params][:crop], filter.inspect
      assert_nil filter[:params][:encode], filter.inspect
      assert_nil filter[:params][:resize], filter.inspect
    end

    test "#encode_to_png?" do
      av = PrimaryAvatar.get @owner
      av.avatar_id = 1
      assert av.encode_to_png?

      av.avatar_id = Avatar::Shared::EARLIEST_FILTERED_ID + 1
      refute av.encode_to_png?
    end

    test "#cropped with dimensions" do
      av = create_avatar_for @newb
      av.update! cropped_x: 1, cropped_y: 2, cropped_width: 3, cropped_height: 4
      primary = PrimaryAvatar.set av, @newb

      assert primary.cropped?
      assert_equal "1,2,3,3", primary.cropped_dimensions
    end

    test "builds url" do
      primary = PrimaryAvatar.get @owner
      assert_equal "#{GitHub.alambic_assets_url}/avatars/#{@avatar2.id}", primary.url
    end

    test "surrogate_key for user avatar" do
      assert_equal "avatars/#{@avatar1.id}", @avatar1.avatar_surrogate_key
    end

    test "surrogate_key for org avatar" do
      assert_equal "avatars/#{@org_avatar1.id}", @org_avatar1.avatar_surrogate_key
    end
  end

  ## PrimaryAvatar tests

  test "PrimaryAvatar.set touches updated_at for the owner" do
    @owner.update_attribute "updated_at", 1.day.ago
    Timecop.freeze(Time.new(2017, 8, 21)) do
      PrimaryAvatar.set @avatar2, @owner
      assert_equal Time.new(2017, 8, 21), @owner.reload.updated_at
    end
  end

  test "builds owner primary url without formatting" do
    GitHub.alambic_avatar_url = "http://alambic.github"
    assert_match /alambic\.github\/u\/\d+\?/, @owner.primary_avatar_url
    assert_match /alambic\.github\/u\/\d+\?/, @owner.static_avatar_url
  end

  test "when in multi tenant, adds only `token` query param when tenant_slug_for_avatar is not for system accounts" do
    on_multi_tenant_enterprise do
      GitHub.flipper[:authenticated_avatars].enable
      @owner.stubs(:tenant_slug_for_avatar).returns("tenant")

      assert_match /token=/, @owner.primary_avatar_url
      assert_match /token=/, @owner.static_avatar_url

      refute_match /entity=/, @owner.primary_avatar_url
      refute_match /entity=/, @owner.static_avatar_url

      GitHub.flipper[:authenticated_avatars].disable

      refute_match /token=/, @owner.primary_avatar_url
      refute_match /token=/, @owner.static_avatar_url

      refute_match /entity=/, @owner.primary_avatar_url
      refute_match /entity=/, @owner.static_avatar_url
    end
  end

  test "when in multi tenant, adds `token` and `entity` query params when `tenant_slug_for_avatar` is for system accounts" do
    on_multi_tenant_enterprise do
      GitHub.flipper[:authenticated_avatars].enable
      @owner.stubs(:tenant_slug_for_avatar).returns(GitHub.company_specific_entity_acronym)

      assert_match /token=/, @owner.primary_avatar_url
      assert_match /token=/, @owner.static_avatar_url

      assert_match /entity=/, @owner.primary_avatar_url
      assert_match /entity=/, @owner.static_avatar_url

      GitHub.flipper[:authenticated_avatars].disable

      refute_match /token=/, @owner.primary_avatar_url
      refute_match /token=/, @owner.static_avatar_url

      refute_match /entity=/, @owner.primary_avatar_url
      refute_match /entity=/, @owner.static_avatar_url
    end
  end

  test "when private_avatars is enabled for requester, uses private avatar url and adds `token` param", skip_in_multitenant_mode: true do
    GitHub.alambic_private_avatar_url = "https://alambic-private.github.test"
    GitHub.context.push(actor_id:  @newb.id)
    GitHub.flipper[:private_avatars].enable(@newb)

    private_primary_avatar_url = @owner.primary_avatar_url
    private_static_avatar_url = @owner.static_avatar_url

    assert_match /alambic-private\.github\.test/, private_primary_avatar_url
    assert_match /alambic-private\.github\.test/, private_static_avatar_url
    assert_match /jwt=/, private_primary_avatar_url
    assert_match /jwt=/, private_static_avatar_url

    GitHub.flipper[:private_avatars].disable(@newb)
    GitHub.context.pop_key(:current_actor_private_avatar_enabled)

    public_primary_avatar_url = @owner.primary_avatar_url
    public_static_avatar_url = @owner.static_avatar_url

    refute_match /alambic-private\.github\.test/, public_primary_avatar_url
    refute_match /alambic-private\.github\.test/, public_static_avatar_url
    refute_match /jwt=/, public_primary_avatar_url
    refute_match /jwt=/, public_static_avatar_url
  end

  test "when private_avatars is enabled for owner, but disabled for requester, uses public avatar url" do
    GitHub.alambic_private_avatar_url = "https://alambic.github.test"
    GitHub.context.push(actor_id:  @newb.id)
    GitHub.flipper[:private_avatars].enable(@owner)
    GitHub.flipper[:private_avatars].disable(@newb)

    private_primary_avatar_url = @owner.primary_avatar_url
    private_static_avatar_url = @owner.static_avatar_url


    assert_match /alambic\.github\.test/, private_primary_avatar_url
    assert_match /alambic\.github\.test/, private_static_avatar_url
    refute_match /jwt=/, private_primary_avatar_url
    refute_match /jwt=/, private_static_avatar_url

    GitHub.flipper[:private_avatars].disable(@owner)
    GitHub.context.pop_key(:current_actor_private_avatar_enabled)

    public_primary_avatar_url = @owner.primary_avatar_url
    public_static_avatar_url = @owner.static_avatar_url

    assert_match /alambic\.github\.test/, public_primary_avatar_url
    assert_match /alambic\.github\.test/, public_static_avatar_url
    refute_match /jwt=/, public_primary_avatar_url
    refute_match /jwt=/, public_static_avatar_url
  end

  test "when crc32 returns 0 for path, it sets nbf without offset" do
    t = Time.new(2024, 1, 1, 0, 5, 5)
    Zlib.stubs(:crc32).returns(0)
    Timecop.freeze(t) do
      expected_time_without_offset = Time.new(2024, 1, 1, 0, 0, 0)
      assert_equal expected_time_without_offset.to_i, PrimaryAvatar.calculate_nbf("/u/test").to_i
    end
  end

  test "when crc32 returns 3 for path, it sets nbf with correct offset" do
    t = Time.new(2024, 1, 1, 0, 5, 5)
    Zlib.stubs(:crc32).returns(3)
    Timecop.freeze(t) do
      expected_time_without_offset = Time.new(2024, 1, 1, 0, 3, 0)
      assert_equal expected_time_without_offset.to_i, PrimaryAvatar.calculate_nbf("/u/test").to_i
    end
  end

  test "when time without offset is in the past, but, with offset is in the future; it returns a date in the past" do
    t = Time.new(2024, 1, 1, 0, 5, 5)
    Zlib.stubs(:crc32).returns(6)
    Timecop.freeze(t) do
      expected_time_without_offset = Time.new(2023, 12, 31, 23, 51, 0)
      assert_equal expected_time_without_offset.to_i, PrimaryAvatar.calculate_nbf("/u/test").to_i
    end
  end

  test "returns value depending depending on crc32 value of path" do
    t = Time.new(2024, 1, 1, 0, 5, 5)
    Zlib.stubs(:crc32).returns(2)
    Zlib.stubs(:crc32).with("/u/test-1").returns(0)
    Zlib.stubs(:crc32).with("/u/test-2").returns(1)
    Timecop.freeze(t) do
      expected_time_without_offset_1 = Time.new(2024, 1, 1, 0, 0, 0)
      expected_time_without_offset_2 = Time.new(2024, 1, 1, 0, 1, 0)
      assert_equal expected_time_without_offset_1.to_i, PrimaryAvatar.calculate_nbf("/u/test-1").to_i
      assert_equal expected_time_without_offset_2.to_i, PrimaryAvatar.calculate_nbf("/u/test-2").to_i
    end
  end

  test "returns same value until it reaches the bucket change time" do
    Zlib.stubs(:crc32).returns(0)
    Timecop.freeze(Time.new(2024, 1, 1, 0, 5, 5)) do
      assert_equal Time.new(2024, 1, 1, 0, 0, 0).to_i, PrimaryAvatar.calculate_nbf("/u/test").to_i
    end
    Timecop.freeze(Time.new(2024, 1, 1, 0, 7, 8)) do
      assert_equal Time.new(2024, 1, 1, 0, 0, 0).to_i, PrimaryAvatar.calculate_nbf("/u/test").to_i
    end
    Timecop.freeze(Time.new(2024, 1, 1, 0, 10, 15)) do
      assert_equal Time.new(2024, 1, 1, 0, 0, 0).to_i, PrimaryAvatar.calculate_nbf("/u/test").to_i
    end
    Timecop.freeze(Time.new(2024, 1, 1, 0, 15, 0)) do
      assert_equal Time.new(2024, 1, 1, 0, 15, 0).to_i, PrimaryAvatar.calculate_nbf("/u/test").to_i
    end
  end

  test "doesn't build token query param if not in multi tenant", skip_in_multitenant_mode: true do
    refute_match /token=/, @owner.primary_avatar_url
    refute_match /token=/, @owner.static_avatar_url

    refute_match /entity=/, @owner.primary_avatar_url
    refute_match /entity=/, @owner.static_avatar_url
  end

  test "returns static `alambic_avatar_url` URL when multi tenant when `authenticated_avatars` is disabled" do
    GitHub.flipper[:authenticated_avatars].disable
    on_multi_tenant_enterprise(tenant: @multi_tenant_business) do
      GitHub.alambic_avatar_url = "http://alambic.github"
      assert_match /alambic\.github\/u\/\d+\?/, @multi_tenant_owner.primary_avatar_url
      assert_match /alambic\.github\/u\/\d+\?/, @multi_tenant_owner.static_avatar_url
    end
  end

  test "returns dynamic tenant URL when multi tenant when `authenticated_avatars` is disabled when `GitHub.alambic_avatar_url` is nil" do
    GitHub.flipper[:authenticated_avatars].disable
    on_multi_tenant_enterprise(tenant: @multi_tenant_business) do
      GitHub.alambic_avatar_url = nil
      assert_match /https:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.ghe\.com\/avatars\/u\/\d+\?/, @multi_tenant_owner.primary_avatar_url
      assert_match /https:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.ghe\.com\/avatars\/u\/\d+\?/, @multi_tenant_owner.static_avatar_url
    end
  end

  test "returns dynamic tenant URL when multi tenant when `authenticated_avatars` is enabled" do
    GitHub.flipper[:authenticated_avatars].enable
    on_multi_tenant_enterprise(tenant: @multi_tenant_business) do
      assert_match /https:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.ghe\.com\/avatars\/u\/\d+\?/, @multi_tenant_owner.primary_avatar_url
      assert_match /https:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.ghe\.com\/avatars\/u\/\d+\?/, @multi_tenant_owner.static_avatar_url
    end
  end

  test "returns dynamic tenant URL when multi tenant when `authenticated_avatars` is enabled even when `GitHub.alambic_avatar_url` is non-nil" do
    GitHub.flipper[:authenticated_avatars].enable
    on_multi_tenant_enterprise(tenant: @multi_tenant_business) do
      GitHub.alambic_avatar_url = "http://alambic.github"
      assert_match /https:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.ghe\.com\/avatars\/u\/\d+\?/, @multi_tenant_owner.primary_avatar_url
      assert_match /https:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.ghe\.com\/avatars\/u\/\d+\?/, @multi_tenant_owner.static_avatar_url
    end
  end

  test "returns dynamic tenant HTTP URL with no port when multi tenant in development environment if SSL is disabled" do
    test_host_name = "github.localhost"
    GitHub.flipper[:authenticated_avatars].enable
    GitHub.stubs(:ssl).returns(false)
    GitHub.stubs(:host_name).returns(test_host_name)
    Rails.env.stubs(:development?).returns(true)
    on_multi_tenant_enterprise(tenant: @multi_tenant_business) do
      assert_match /http:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.#{test_host_name}\/alambic\/avatars\/u\/\d+\?/, @multi_tenant_owner.primary_avatar_url
      assert_match /http:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.#{test_host_name}\/alambic\/avatars\/u\/\d+\?/, @multi_tenant_owner.static_avatar_url
    end
  end

  test "returns dynamic tenant HTTP URL with port when multi tenant in development environment if SSL is disabled" do
    test_host_name = "github.localhost:81"
    GitHub.flipper[:authenticated_avatars].enable
    GitHub.stubs(:ssl).returns(false)
    GitHub.stubs(:host_name).returns(test_host_name)
    Rails.env.stubs(:development?).returns(true)
    on_multi_tenant_enterprise(tenant: @multi_tenant_business) do
      assert_match /http:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.#{test_host_name}\/alambic\/avatars\/u\/\d+\?/, @multi_tenant_owner.primary_avatar_url
      assert_match /http:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.#{test_host_name}\/alambic\/avatars\/u\/\d+\?/, @multi_tenant_owner.static_avatar_url
    end
  end

  test "returns dynamic tenant HTTPS URL with no port when multi tenant in development environment if SSL is disabled" do
    test_host_name = "github.localhost"
    GitHub.flipper[:authenticated_avatars].enable
    GitHub.stubs(:ssl).returns(true)
    GitHub.stubs(:host_name).returns(test_host_name)
    Rails.env.stubs(:development?).returns(true)
    on_multi_tenant_enterprise(tenant: @multi_tenant_business) do
      assert_match /https:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.#{test_host_name}\/alambic\/avatars\/u\/\d+\?/, @multi_tenant_owner.primary_avatar_url
      assert_match /https:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.#{test_host_name}\/alambic\/avatars\/u\/\d+\?/, @multi_tenant_owner.static_avatar_url
    end
  end

  test "returns dynamic tenant HTTPS URL with port when multi tenant in development environment if SSL is disabled" do
    test_host_name = "github.localhost:81"
    GitHub.flipper[:authenticated_avatars].enable
    GitHub.stubs(:ssl).returns(true)
    GitHub.stubs(:host_name).returns(test_host_name)
    Rails.env.stubs(:development?).returns(true)
    on_multi_tenant_enterprise(tenant: @multi_tenant_business) do
      assert_match /https:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.#{test_host_name}\/alambic\/avatars\/u\/\d+\?/, @multi_tenant_owner.primary_avatar_url
      assert_match /https:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.#{test_host_name}\/alambic\/avatars\/u\/\d+\?/, @multi_tenant_owner.static_avatar_url
    end
  end

  test "returns dynamic tenant URL scoped to entity's tenant when requested from different tenant" do
    GitHub.flipper[:authenticated_avatars].enable

    on_multi_tenant_enterprise(tenant: create(:business)) do
      assert_match /https:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.ghe\.com\/avatars\/u\/\d+\?/, @multi_tenant_owner.primary_avatar_url
      assert_match /https:\/\/#{@multi_tenant_owner.tenant_slug_for_avatar}\.ghe\.com\/avatars\/u\/\d+\?/, @multi_tenant_owner.static_avatar_url
    end
  end

  test "returns dynamic tenant URL scoped to current tenant when requested from different tenant if entity cannot introspect its tenant" do
    GitHub.flipper[:authenticated_avatars].enable

    @multi_tenant_owner.stubs(:tenant_slug_for_avatar).raises(NotImplementedError)
    business = create(:business)
    on_multi_tenant_enterprise(tenant: business) do
      expected_keys = { "gh.avatars.entity.class": @multi_tenant_owner.class.name, "gh.avatars.path": @multi_tenant_owner.primary_avatar_path }
      assert_logged(**expected_keys) do
        assert_match /https:\/\/#{business}\.ghe\.com\/avatars\/u\/\d+\?/, @multi_tenant_owner.primary_avatar_url
        assert_match /https:\/\/#{business}\.ghe\.com\/avatars\/u\/\d+\?/, @multi_tenant_owner.static_avatar_url
      end
    end
  end

  test "returns dynamic URL scoped to current tenant when requesting a system account avatar (entity whose tenant is the company specific acronym)" do
    GitHub.flipper[:authenticated_avatars].enable
    on_multi_tenant_enterprise(tenant: @multi_tenant_business) do
      assert_match /https:\/\/#{@multi_tenant_business.slug}\.ghe\.com\/avatars\/u\/\d+\?.*entity=#{GitHub.company_specific_entity_acronym}.*/, User.ghost.primary_avatar_url
      assert_match /https:\/\/#{@multi_tenant_business.slug}\.ghe\.com\/avatars\/u\/\d+\?.*entity=#{GitHub.company_specific_entity_acronym}.*/, User.ghost.static_avatar_url
    end
  end

  test "returns relative URL when multi tenant and no tenant" do
    on_multi_tenant_enterprise(tenant: nil) do
      GitHub.alambic_avatar_url = nil
      assert_match /avatars\/u\/\d+\?/, @owner.primary_avatar_url
      assert_match /avatars\/u\/\d+\?/, @owner.static_avatar_url
    end
  end

  test "initial primary avatar has no previous" do
    assert_nil PrimaryAvatar.get(@owner).previous_avatar
  end

  test "gets primary avatar for user" do
    primary = assert_primary_avatar @avatar2, @owner
    assert_equal @owner, primary.updater
  end

  test "sets user primary avatar manually" do
    new_user_avatar = create_avatar_for @owner
    assert_primary_avatar @avatar2, @owner

    primary = PrimaryAvatar.set new_user_avatar, @owner

    assert_primary_avatar new_user_avatar, @owner
    assert_equal @owner, primary.updater
    assert !Avatar.exists?(@avatar2.id)
  end

  test "sets organization primary avatar manually" do
    new_org_avatar = create_avatar_for @org
    assert_primary_avatar @org_avatar1, @org

    primary = PrimaryAvatar.set new_org_avatar, @org

    assert_primary_avatar new_org_avatar, @org
    assert_equal @org, primary.updater
    assert !Avatar.exists?(@org_avatar1.id)
  end

  context "instrumentation" do
    include HydroTestHelpers

    test "instrument setting an avatar" do
      events = subscribe "profile_picture.update"

      PrimaryAvatar.set @avatar1, @owner

      expected_payload = {
        user: @avatar1.owner.display_login,
        user_id: @avatar1.owner.id,
        owner: @avatar1.owner.display_login,
        owner_id: @avatar1.owner.id,
        actor: @owner.display_login,
        actor_id: @owner.id,
        type: "User",
      }

      assert event = events.pop, "an event was expected"
      assert_equal "profile_picture.update", event.name
      assert_equal expected_payload, event.payload
    end

    test "issue_comment create event is published to hydro" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        GitHub.context.push(actor_ip: "1.2.3.4")
        GitHub.context.push(user_agent: "test agent")

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(@owner),
          avatar: Hydro::EntitySerializer.avatar(@avatar1),
        }

        PrimaryAvatar.set @avatar1, @owner

        assert_hydro_published(message, schema: "github.v1.PrimaryAvatarUpdate")
      end
    end

    test "doesn't instrument when avatar doesn't exist" do
      user = create(:user)
      avatar = create_avatar_for user
      primary_avatar = PrimaryAvatar.set avatar, user

      events = subscribe "profile_picture.update"
      primary_avatar.avatar = nil
      primary_avatar.send :instrument_update

      assert_equal 0, events.size, "Didn't expect an event"
    end

    test "instrument setting an org avatar" do
      events = subscribe "profile_picture.update"
      PrimaryAvatar.set @org_avatar1, @owner

      expected_payload = {
        type: "Organization",
        actor: @owner.display_login,
        actor_id: @owner.id,
        owner: @org_avatar1.owner.display_login,
        owner_id: @org_avatar1.owner.id,
        org: @org_avatar1.owner.display_login,
        org_id: @org_avatar1.owner.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "profile_picture.update", event.name
      assert_equal expected_payload, event.payload
    end

    test "instrument setting an OAuth app avatar" do
      events = subscribe "profile_picture.update"

      app = create :oauth_application, user: @owner
      meta = {
        size: 42,
        content_type: "image/png",
        width: 5,
        height: 6,
        owner_id: app.id,
        owner_type: "OauthApplication",
      }
      avatar = Avatar.upload(@owner, Sham.sha256, meta)
      PrimaryAvatar.set avatar, @owner

      expected_payload = {
        type: "OauthApplication",
        actor: @owner.display_login,
        actor_id: @owner.id,
        owner: avatar.owner.name,
        owner_id: avatar.owner.id,
        oauth_application: avatar.owner.name,
        oauth_application_id: avatar.owner.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "profile_picture.update", event.name
      assert_equal expected_payload, event.payload
    end
  end

  test "set! recovers from unique index race condition" do
    # create a subclass of PrimaryAvatar so that PrimaryAvatar.get returns nil
    # once, and PrimaryAvatar.set initializes a new record.
    avatar_class = Class.new(PrimaryAvatar)
    def avatar_class.name() "FakePrimaryAvatar" end

    class << avatar_class
      attr_accessor :returned_nil
    end

    def avatar_class.get(owner)
      if @returned_nil
        super(owner)
      else
        @returned_nil = true
        nil
      end
    end

    assert_equal @avatar2, PrimaryAvatar.get(@owner).avatar
    refute avatar_class.returned_nil
    avatar_class.set!(@avatar1, @owner)
    assert avatar_class.returned_nil
    assert_equal @avatar1, PrimaryAvatar.get(@owner).avatar
  end

  test "set! only retries once" do
    # create a subclass of PrimaryAvatar so that PrimaryAvatar.get returns nil
    # twice, and PrimaryAvatar.set initializes a new record.
    avatar_class = Class.new(PrimaryAvatar)
    def avatar_class.name() "FakePrimaryAvatar" end

    class << avatar_class
      attr_accessor :nil_returns
    end

    # return nil twice
    avatar_class.nil_returns = 2
    def avatar_class.get(owner)
      if @nil_returns > 0
        @nil_returns -= 1
        nil
      else
        super(owner)
      end
    end

    assert_equal @avatar2, PrimaryAvatar.get(@owner).avatar

    assert_raises ActiveRecord::RecordInvalid do
      avatar_class.set! @avatar1, @owner
    end

    assert_equal @avatar2, PrimaryAvatar.get(@owner).avatar
  end

  test "cannot save other user avatar" do
    assert_raises ActiveRecord::RecordInvalid do
      PrimaryAvatar.set @avatar1, @newb
    end

    assert_raises ActiveRecord::RecordInvalid do
      PrimaryAvatar.set! @avatar1, @newb
    end
  end

  test "cannot save unowned org avatar" do
    assert_raises ActiveRecord::RecordInvalid do
      PrimaryAvatar.set @org_avatar1, @newb
    end

    assert_raises ActiveRecord::RecordInvalid do
      PrimaryAvatar.set! @org_avatar1, @newb
    end
  end

  test "gets primary and all other avatars" do
    assert_equal [@avatar2, [@avatar1]], @owner.all_avatars
  end

  test "gets primary and paginated avatars" do
    avatars = 30.times.map { create_avatar_for(@owner) }
    assert_equal [@avatar2, avatars.reverse], @owner.all_avatars
  end

  test "attempts primary avatar when owner has no avatars" do
    assert_nil @newb.primary_avatar

    assert_no_queries do
      assert_nil @newb.primary_avatar
    end
  end

  test "rejects second PrimaryAvatar for a user" do
    primary = PrimaryAvatar.get @owner
    primary2 = PrimaryAvatar.new owner: @owner, avatar: @avatar1
    assert !primary2.valid?
    assert primary2.errors[:owner_id].present?
  end

  test "allows duplicate owner_id with different owner type" do
    primary = PrimaryAvatar.get @org
    primary2 = PrimaryAvatar.new updater: @owner, avatar: @org_avatar1,
      owner_id: @org.id, owner_type: "Organization"
    assert_valid primary2
  end

  test "purges cdn on create" do
    PrimaryAvatar.delete_all
    keys = [User::AvatarList.surrogate_key(@owner), @avatar1.surrogate_key]
    assert_purged_keys(*keys) do
      PrimaryAvatar.set @avatar1, @owner
    end
  end

  test "purges cdn on save" do
    avatar1_key = @avatar1.surrogate_key
    owner_key = User::AvatarList.surrogate_key @owner
    owner_av1_key = "#{avatar1_key},#{owner_key}"
    avatar2_key = @avatar2.surrogate_key # avatar2 will be deleted on PrimaryAvatar.set and consequently purged
    keys = [owner_av1_key, avatar2_key]

    assert_purged_keys(*keys) do
      PrimaryAvatar.set @avatar1, @owner
    end
  end

  test "purges cdn after updating coordinates" do
    owner_key = User::AvatarList.surrogate_key(@owner)
    avatar1_key = @avatar1.surrogate_key
    owner_av1_key = "#{avatar1_key},#{owner_key}"
    avatar2_key = @avatar2.surrogate_key # avatar2 will be deleted on PrimaryAvatar.set and consequently purged
    keys = [owner_av1_key, avatar1_key, avatar2_key]

    assert_purged_keys(*keys) do
      @avatar1.cropped_x = @avatar1.cropped_x + 1
      @avatar1.save!
      PrimaryAvatar.set @avatar1, @owner
    end
  end

  test "purges cdn on destroy" do
    keys = [User::AvatarList.surrogate_key(@owner), @avatar2.surrogate_key]
    assert_purged_keys(*keys) do
      PrimaryAvatar.get(@owner).destroy
    end
  end

  test "notify failbot on invalid purge" do
    keys = [User::AvatarList.surrogate_key(@owner), @avatar1.surrogate_key]
    assert_failed_purge(*keys) do
      assert_raises AssetUploadable::Cdn::Error do
        PrimaryAvatar.set @avatar1, @owner
      end
    end
  end

  context "Avatar config" do
    test "get avatar version" do
      GitHub.alambic_next_avatar_version = "10000"
      refute_equal GitHub.alambic_avatar_version, GitHub.alambic_next_avatar_version
      assert_equal GitHub.alambic_avatar_version, GitHub.avatar_version
    end

    test "get avatar version with really low chance" do
      GitHub.alambic_next_avatar_chance = "-1"
      GitHub.alambic_next_avatar_version = "10000"
      refute_equal GitHub.alambic_avatar_version, GitHub.alambic_next_avatar_version
      assert_equal GitHub.alambic_avatar_version, GitHub.avatar_version
    end

    test "get avatar version with high chance and next version" do
      GitHub.alambic_next_avatar_chance = "100"
      refute_equal GitHub.alambic_avatar_version, GitHub.alambic_next_avatar_version
      assert_equal GitHub.alambic_avatar_version, GitHub.avatar_version
    end

    test "get next avatar version" do
      GitHub.alambic_next_avatar_chance = "100"
      GitHub.alambic_next_avatar_version = "10000"
      refute_equal GitHub.alambic_avatar_version, GitHub.alambic_next_avatar_version
      assert_equal GitHub.alambic_next_avatar_version, GitHub.avatar_version
    end

    test "get browser avatar version" do
      GitHub.alambic_next_browser_avatar_version = "10000"
      refute_equal GitHub.alambic_browser_avatar_version, GitHub.alambic_next_browser_avatar_version
      assert_equal GitHub.alambic_browser_avatar_version, GitHub.browser_avatar_version
    end

    test "get browser avatar version with really low chance" do
      GitHub.alambic_next_avatar_chance = "-1"
      GitHub.alambic_next_browser_avatar_version = "10000"
      refute_equal GitHub.alambic_browser_avatar_version, GitHub.alambic_next_browser_avatar_version
      assert_equal GitHub.alambic_browser_avatar_version, GitHub.browser_avatar_version
    end

    test "get browser avatar version with high chance and next version" do
      GitHub.alambic_next_avatar_chance = "100"
      refute_equal GitHub.alambic_browser_avatar_version, GitHub.alambic_next_browser_avatar_version
      assert_equal GitHub.alambic_browser_avatar_version, GitHub.browser_avatar_version
    end

    test "get browser next avatar version" do
      GitHub.alambic_next_avatar_chance = "100"
      GitHub.alambic_next_browser_avatar_version = "10000"
      refute_equal GitHub.alambic_browser_avatar_version, GitHub.alambic_next_browser_avatar_version
      assert_equal GitHub.alambic_next_browser_avatar_version, GitHub.browser_avatar_version
    end
  end

  context "#self.generate_token_for" do
    test "returns valid hamc token" do
      PrimaryAvatar.unstub(:generate_token_for)
      tenant = "the-tenant"
      path = "/u/1"
      secret, time_now = generate_token_method_stubs

      token = PrimaryAvatar.generate_token_for(tenant, path)
      decoded_token = Base64.decode64(token)
      timestamp, received_hmac = decoded_token.split(".")
      data = "AvatarFetcher/#{time_now.to_i}/#{tenant}/#{path}"

      assert_equal time_now.to_i.to_s, timestamp
      assert SecurityUtils.secure_compare(
        received_hmac,
        OpenSSL::HMAC.hexdigest(GitHub::RequestHmacValidator::HMAC_ALGORITHM, secret, data)
      )
    end

    test "returns base64 encoded token" do
      PrimaryAvatar.unstub(:generate_token_for)
      generate_token_method_stubs

      token = PrimaryAvatar.generate_token_for("the-tenant", "/u/1")
      assert_nothing_raised { Base64.strict_decode64(token) }
    end

    test "creates HMAC with the correct algorithm" do
      PrimaryAvatar.unstub(:generate_token_for)
      generate_token_method_stubs

      algorithm = GitHub::RequestHmacValidator::HMAC_ALGORITHM
      OpenSSL::HMAC.expects(:hexdigest).with(algorithm, anything, anything).returns("abc123") # rubocop:disable GitHub/InsecureHashAlgorithm

      PrimaryAvatar.generate_token_for("the-tenant", "/u/1")
    end
  end

  context "#self.add_token_and_entity_to_query" do
    context "in multi tenant" do
      test "adds token and entity to query" do
        token, path = generate_add_token_and_entity_to_query_method_stubs

        query = PrimaryAvatar.add_token_and_entity_to_query({}, nil, path)

        assert query.has_key?(:token) && query.has_key?(:entity)
        assert_equal token, query[:token]
        assert_equal GitHub.company_specific_entity_acronym, query[:entity]
      end

      test "it doesn't add entity to query if `tenant_slug_for_avatar` is different from `company_specific_entity_acronym`" do
        _, path = generate_add_token_and_entity_to_query_method_stubs

        query = PrimaryAvatar.add_token_and_entity_to_query({}, EntitySupportedInProxima.new, path)

        assert query.has_key?(:token)
        refute query.has_key?(:entity)
      end

      test "it doesn't add entity to query if model that includes `PrimaryAvatar::Model` doesn't implement `tenant_slug_for_avatar`" do
        _, path = generate_add_token_and_entity_to_query_method_stubs

        query = PrimaryAvatar.add_token_and_entity_to_query({}, Marketplace::Listing.new, path)

        refute query.has_key?(:token)
        refute query.has_key?(:entity)
      end
    end
  end

  def generate_token_method_stubs
    secret = "secret"
    time_now = Time.new(2023, 8, 22)

    GitHub.stubs(:alambic_avatars_hmac_key).returns(secret)
    Time.stubs(:now).returns(time_now)

    [secret, time_now]
  end

  def generate_add_token_and_entity_to_query_method_stubs
    path = "/u/1"
    token = Base64.strict_encode64("abcd1234")

    GitHub.flipper[:authenticated_avatars].enable
    GitHub.stubs(:multi_tenant_enterprise?).returns(true)
    PrimaryAvatar.stubs(:generate_token_for).returns(token)

    [token, path]
  end

  def create_avatar_for(owner)
    avatar = Avatar.upload(owner, Sham.sha256, avatar_attrs(owner))
    assert !avatar.new_record?, "avatar for #{owner.class} #{owner} did not save: #{avatar.errors.full_messages.to_sentence}"
    assert_equal owner, avatar.owner
    avatar
  end

  def avatar_attrs(owner)
    {
      size: 42,
      content_type: "image/png",
      width: 5,
      height: 6,
      owner_id: owner.id,
      owner_type: "User",
    }
  end

  def assert_primary_avatar(expected, owner)
    if expected
      assert primary = PrimaryAvatar.get(owner), "no primary set for #{owner.inspect}"
      assert_equal expected, primary.avatar
      assert_equal expected.cropped_x, primary.cropped_x
      assert_equal expected.cropped_y, primary.cropped_y
      assert_equal expected.cropped_width, primary.cropped_width
      assert_equal expected.cropped_height, primary.cropped_height
      primary
    else
      assert_nil owner.primary_avatar
      nil
    end
  end
end

# Classes for testing `PrimaryAvatar.add_token_and_entity_to_query` method
class EntitySupportedInProxima
  def tenant_slug_for_avatar
    "the-tenant"
  end
end
