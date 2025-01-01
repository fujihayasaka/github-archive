# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersUserFilterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")
    @twp     = create(:user, login: "TwP")
    @bot     = create(:integration).bot
  end

  setup do
    @quals = Search::ParsedQuery.qualifiers
  end

  test "generates an include filter" do
    @quals[:user].must "defunkt"
    filter = Search::Filters::UserFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    assert_equal({ term: { user_id: @defunkt.id } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "generates an include filter for bots" do
    @quals[:user].must Bot.query_filter_from_login(@bot.display_login)
    filter = Search::Filters::UserFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    assert_equal({ term: { user_id: @bot.id } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "removes excluded users from the include filter" do
    @quals[:user].must %w[defunkt mojombo TwP]
    @quals[:user].must_not "mojombo"
    filter = Search::Filters::UserFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    assert_equal({ terms: { user_id: [@defunkt.id, @twp.id] } }, filter.must)
    assert filter.valid?
  end

  test "generates an exclude filter" do
    @quals[:user].must_not "mojombo"
    filter = Search::Filters::UserFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    assert_equal({ term: { user_id: @mojombo.id } }, filter.must_not)
    assert filter.valid?
  end

  test "generates an exclude filter for bots" do
    @quals[:user].must_not Bot.query_filter_from_login(@bot.display_login)
    filter = Search::Filters::UserFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    assert_equal({ term: { user_id: @bot.id } }, filter.must_not)
    assert filter.valid?
  end

  test "ignores spammy users" do
    @quals[:user].must %w[TwP hushpuppy1234]
    filter = Search::Filters::UserFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    assert_equal({ term: { user_id: @twp.id } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  context "with non-existent users" do
    test "the filter will be invalid" do
      @quals[:user].must "non-existent-user"
      filter = Search::Filters::UserFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

      assert_nil filter.must
      assert !filter.valid?
    end

    test "the filter will valid" do
      @quals[:user].must "twp"
      @quals[:user].must_not "non-existent-user"
      filter = Search::Filters::UserFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

      assert_equal({ term: { user_id: @twp.id } }, filter.must)
      assert_nil filter.must_not
      assert !filter.valid?
    end
  end

  context "degenerate inputs" do
    test "creates a valid filter" do
      @quals[:user].must "mojombo"
      @quals[:user].must_not "mojombo"
      filter = Search::Filters::UserFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

      assert_nil filter.must
      assert_equal({ term: { user_id: @mojombo.id } }, filter.must_not)
      assert filter.valid?, "filter should be valid"
    end

    test "still creates a valid filter" do
      @quals[:user].must %w[defunkt mojombo]
      @quals[:user].must_not "mojombo"
      filter = Search::Filters::UserFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

      assert_equal({ term: { user_id: @defunkt.id } }, filter.must)
      assert_equal({ term: { user_id: @mojombo.id } }, filter.must_not)
      assert filter.valid?, "filter should be valid"
    end
  end

  context "exists and missing (must-not-exists) filters" do
    test "creates an exists filter" do
      @quals[:user].must :exists
      filter = Search::Filters::UserFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

      assert_equal({ exists: { field: :user_id } }, filter.must)
      assert filter.valid?, "filter should be valid"
    end

    test "creates a missing (must-not-exists) filter" do
      @quals[:user].must :missing
      filter = Search::Filters::UserFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

      assert_equal({ bool: { must_not: { exists: { field: :user_id } } } }, filter.must)
      assert filter.valid?, "filter should be valid"
    end
  end

  context "for private profiles" do
    test "when exclude_private_profile option is set ignores private profiles" do
      enable_feature_flag(:invalidate_private_profile_searches)
      @private_profile = create(:user, login: "privateProfile", private_profile: true)
      @quals[:user].must %w[privateProfile TwP]
      filter = Search::Filters::UserFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: true)

      assert_equal({ term: { user_id: @twp.id } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
    end

    test "when exclude_private_profile option is not set returns private profiles" do
      enable_feature_flag(:invalidate_private_profile_searches)
      @private_profile = create(:user, login: "privateProfile", private_profile: true)
      @quals[:user].must "privateProfile"
      filter = Search::Filters::UserFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

      assert_equal({ term: { user_id: @private_profile.id } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
    end
  end
end

class SearchFiltersUserFilterIpAllowListEnforcementTest < GitHub::TestCase
  skip_unless :ip_allowlists_available?

  include ConditionalAccess::FilterTestHelper

  fixtures do
    @twp = create(:user, login: "TwP", skip_enterprise_managed_user: true)

    @emu = create :emu
    @emu_business = @emu.enterprise_managed_business
    @other_emu = create :emu, business: @emu_business
    enable_feature_flag(:ip_allowlist_user_level_enforcement, @emu_business)
    create :ip_allowlist_entry, owner: @emu_business, active: true, allow_list_value: "10.10.10.0/24"
    @emu_business.enable_ip_allowlist(actor: @emu_business.owners.first)
    @emu_business.enable_ip_allowlist_user_level_enforcement(actor: @emu_business.owners.first)
  end

  setup do
    enable_feature_flag(:ip_allowlist_user_level_enforcement, @emu_business)
    @quals = Search::ParsedQuery.qualifiers
  end

  test "as EMU with allowed IP, returns other EMUs" do
    mock_filter = cap_authorizing_filter([@other_emu])

    @quals[:user].must [@twp.display_login, @other_emu.display_login]
    filter = Search::Filters::UserFilter.new(
      keys: :user,
      qualifiers: @quals,
      current_user: @emu,
      cap_filter: mock_filter,
      exclude_private_profiles: false
    )

    assert_equal({ terms: { user_id: [@twp.id, @other_emu.id] } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "as EMU with forbidden IP, ignores other EMUs" do
    mock_filter = cap_unauthorizing_filter([@other_emu], :ip_allowlist)

    @quals[:user].must [@twp.display_login, @other_emu.display_login]
    filter = Search::Filters::UserFilter.new(
      keys: :user,
      qualifiers: @quals,
      current_user: @emu,
      cap_filter: mock_filter,
      exclude_private_profiles: false
    )

    assert_equal({ term: { user_id: @twp.id } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end
end

class SearchFiltersUserFilterExternalCAPEnforcementTest < GitHub::TestCase
  skip_unless :idp_cap_available?

  include ConditionalAccess::FilterTestHelper
  include AuthenticationHelpers::OIDC

  fixtures do
    @twp = create(:user, login: "TwP", skip_enterprise_managed_user: true)

    @emu = create :emu, :owner, provider_type: :oidc
    @emu_business = @emu.enterprise_managed_business
    @other_emu = create :emu, business: @emu_business

    @emu_business.update_ip_allowlist_configuration(actor: @emu, config_value: Configurable::IpAllowlistConfiguration::IDP)
    @emu_business.reload
    assert_predicate @emu_business, :idp_based_ip_allowlist_configuration?
  end

  setup do
    @tenant_provider = ::OIDC::TenantProvider.new(@emu_business)
    disable_feature_flag(:disable_oidc_cap_cache)
    @emu_business.enable_idp_ip_allowlist_for_web(actor: @emu)
    @quals = Search::ParsedQuery.qualifiers
  end

  test "as EMU with successful external CAP, returns other EMUs" do
    mock_filter = cap_authorizing_filter([@other_emu])

    @quals[:user].must [@twp.display_login, @other_emu.display_login]
    filter = Search::Filters::UserFilter.new(
      keys: :user,
      qualifiers: @quals,
      current_user: @emu,
      cap_filter: mock_filter,
      exclude_private_profiles: false
    )

    assert_equal({ terms: { user_id: [@twp.id, @other_emu.id] } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "as EMU with failed external CAP, returns other EMUs" do
    mock_filter = cap_unauthorizing_filter([@other_emu], :external_conditional_access_policy)

    @quals[:user].must [@twp.display_login, @other_emu.display_login]
    filter = Search::Filters::UserFilter.new(
      keys: :user,
      qualifiers: @quals,
      current_user: @emu,
      cap_filter: mock_filter,
      exclude_private_profiles: false
    )

    assert_equal({ terms: { user_id: [@twp.id, @other_emu.id] } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end
end
