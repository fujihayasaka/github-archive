# typed: true
# frozen_string_literal: true

require "test_helper"

class ProfileTest < GitHub::TestCase
  include HydroTestHelpers
  include StringFromBinaryTestHelper
  include GitHub::DatabaseQueryWarningsTestHelpers

  fixtures do
    @native_emoji_string = "Grin #{GRIN_EMOJI} Emoji"
    @native_emoji_string2 = "Grin \xF0\x9F\x98\x80 Emoji"
  end

  context "sponsors_listing_stafftools_metadata relation" do
    test "returns the Sponsors stafftools metadata record for the profile's user" do
      stafftools_metadata = create(:sponsors_listing_stafftools_metadata)
      user = stafftools_metadata.sponsorable
      profile = create(:profile, user: user)
      assert_equal stafftools_metadata, profile.sponsors_listing_stafftools_metadata
    end

    test "returns nil when no Sponsors stafftools metadata record exists for the profile's user" do
      profile = create(:profile)
      assert_nil profile.sponsors_listing_stafftools_metadata
    end
  end

  test "does not allow high unicode in profile email" do
    profile = build(:profile)
    profile["email"] = @native_emoji_string
    refute profile.valid?, "should be invalid due to high unicode in email"
    assert_equal "doesn't accept 4-byte Unicode", profile.errors["email"].first
  end

  %w[name bio blog company location].each do |field|
    test "allows high unicode in profile #{field}" do
      profile = build(:profile)
      profile[field] = @native_emoji_string
      assert_predicate profile, :valid?, "should be valid with high unicode in #{field}"
      assert profile.save
      assert_equal @native_emoji_string, profile.reload[field]
    end
  end

  test "does not allow silent truncation of strings" do
    fields = %w[name email blog company location]
    fields.each do |field|
      profile = build(:profile)
      profile[field] = "a" * 256
      refute profile.valid?
      assert_equal "is too long (maximum is 255 characters)",
                   profile.errors[field].first
    end
  end

  fields = %w[name email blog company location]
  fields.each do |field|
    test "coerces blank #{field} value to nil" do
      profile = build(:profile)
      profile[field] = ""
      assert profile.valid?
      assert_nil profile[field]
    end
  end

  test "allows emoji in bio field" do
    profile = build(:profile)
    profile.bio = @native_emoji_string
    profile.save

    assert profile.valid?
    assert_equal @native_emoji_string, profile.reload.bio
    assert_multibyte_tracked_changes(profile, :bio, @native_emoji_string, @native_emoji_string2)
  end

  test "limits length of bio field" do
    bio = "a" * 161
    refute build(:profile, bio: bio).valid?
  end

  test "limits length of pronouns field" do
    profile = build(:profile)
    profile.pronouns = "a" * 48
    assert_predicate profile, :valid?
    profile.pronouns = "a" * 49
    refute_predicate profile, :valid?
  end

  test "pronouns allow 4-byte UTF-8 (for more modern/inclusive emoji)" do
    pronouns = "ze/hir ✨💻🧕🤱🏽✨"
    profile = build(:profile)
    profile.pronouns = pronouns
    profile.save!
    assert_equal pronouns, profile.reload.pronouns
  end

  test "allows valid time zone names" do
    mobile_time_zone_name = "America/Chicago"
    assert build(:profile, mobile_time_zone_name: mobile_time_zone_name).valid?
  end

  test "limits length of mobile_time_zone field" do
    mobile_time_zone_name = "a" * 41
    refute build(:profile, mobile_time_zone_name: mobile_time_zone_name).valid?
  end

  test "does not allow invalid time zone names" do
    mobile_time_zone_name = "America/Invalid_Name"
    refute build(:profile, mobile_time_zone_name: mobile_time_zone_name).valid?
  end

  test "requires a user" do
    profile = Profile.new
    refute_predicate profile, :valid?
    assert_includes profile.errors[:user], "can't be blank"
  end

  test "requires a unique user" do
    existing_profile = create(:profile)
    dupe_profile = build(:profile, user: existing_profile.user)

    refute_predicate dupe_profile, :valid?
    assert_includes dupe_profile.errors[:user], "has already been taken"
  end

  context "when a new attribute is in the db but not the schema" do
    test "it successfully updates the record and instruments the update" do
      profile = create(:profile)
      profile.stubs(attributes: profile.attributes.merge(new_column: "hi"))

      GlobalInstrumenter.expects(:instrument).once
      profile.update(bio: "sweet tooth")

      assert_equal profile.bio, "sweet tooth"
    end
  end

  test "instruments update and publishes to hydro" do
    user = create(:user)
    user.profile_name = "donut"
    user.profile_social_accounts = [
      create(:social_account_twitter, url: "https://twitter.com/monalisa"),
      create(:social_account_linkedin, url: "https://linkedin.com/in/monalisa"),
    ]
    user.save!
    previous_profile = Profile.find(user.profile.id)
    now = user.profile.reload.created_at

    GitHub.stubs(:hydro_enabled?).returns(true)

    Timecop.freeze(now) do
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub.context.push(user_agent: "test agent")

      user.profile_bio = "sweet tooth"
      user.profile_location = "Elkhart Indiana"
      user.profile_pronouns = "she/her"
      user.profile_social_accounts = [
        create(:social_account_linkedin, url: "https://linkedin.com/in/monalisa"),
        create(:social_account_mastodon, url: "https://mastodon.social/@monalisa"),
      ]
      user.save!

      serialized_previous_social_accounts = previous_profile.social_accounts.map do |account|
        Hydro::EntitySerializer.social_account(account)
      end

      serialized_current_social_accounts = user.profile.social_accounts.map do |account|
        Hydro::EntitySerializer.social_account(account)
      end

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(user),
        previous_profile: Hydro::EntitySerializer.profile(previous_profile),
        current_profile: Hydro::EntitySerializer.profile(user.profile),
        changed_attribute_names: user.profile.saved_changes.keys - Profile::CHANGED_ATTRIBUTES_TO_IGNORE,
        specimen_company: Hydro::EntitySerializer.specimen_data(user.profile.company),
        specimen_location: Hydro::EntitySerializer.specimen_data(user.profile.location),
        specimen_name: Hydro::EntitySerializer.specimen_data(user.profile.name),
        specimen_website_url: Hydro::EntitySerializer.specimen_data(user.profile.blog),
        previous_social_accounts: serialized_previous_social_accounts,
        current_social_accounts: serialized_current_social_accounts,
      }

      assert_hydro_published(message, schema: "github.v1.ProfileUpdate")
    end
  end

  test "Profile update publishes github.v1.SocialAccountCreate and github.v1.SocialAccountDestroy" do
    twitter_account = create(:social_account_twitter)
    linkedin_account = create(:social_account_linkedin)
    mastodon_account = create(:social_account_mastodon)
    facebook_account = create(:social_account_facebook)
    twitch_account = create(:social_account_twitch)
    youtube_account = create(:social_account_youtube)

    user = create(:user)
    user.profile_social_accounts = [twitter_account, linkedin_account, mastodon_account, facebook_account]
    user.save!
    previous_profile = Profile.find(user.profile.id)
    now = user.profile.reload.created_at

    GitHub.stubs(:hydro_enabled?).returns(true)

    user.profile_social_accounts = [linkedin_account, facebook_account, twitch_account, youtube_account]
    user.save!

    creation_message_for = ->(account) do
      {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(user),
        spamurai_form_signals: nil,
        social_account: Hydro::EntitySerializer.social_account(account),
      }
    end

    assert_hydro_published(creation_message_for.call(twitch_account), schema: "github.v1.SocialAccountCreate")
    assert_hydro_published(creation_message_for.call(youtube_account), schema: "github.v1.SocialAccountCreate")

    deletion_message_for = ->(account) do
      {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(user),
        social_account: Hydro::EntitySerializer.social_account(account),
      }
    end

    assert_hydro_published(deletion_message_for.call(twitter_account), schema: "github.v1.SocialAccountDestroy")
    assert_hydro_published(deletion_message_for.call(mastodon_account), schema: "github.v1.SocialAccountDestroy")
  end

  test "Profile update publishes github.platform_health.v1.UserGeneratedContent" do
    GitHub.stubs(:hydro_enabled?).returns(true)

    user = create(:user)
    user.profile_name = "donut"
    user.profile_bio = "sweet tooth"
    user.save

    message = {
      request_context: nil,
      spamurai_form_signals: nil,
      action_type: :UPDATE,
      content_type: :PROFILE_BIO,
      actor: Hydro::EntitySerializer.user(user),
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.ProfileUpdate"),
      content_database_id: user.profile.id,
      content_global_relay_id: user.profile.global_relay_id,
      content_created_at: user.profile.created_at,
      content_updated_at: user.profile.updated_at,
      title: Hydro::EntitySerializer.specimen_data(user.profile.name),
      content: Hydro::EntitySerializer.specimen_data(user.profile.bio),
      parent_content_author: nil,
      parent_content_database_id: nil,
      parent_content_global_relay_id: nil,
      parent_content_created_at: nil,
      parent_content_updated_at: nil,
      owner: Hydro::EntitySerializer.user(user),
      repository: nil,
      content_visibility: :PUBLIC,
      content_url: Hydro::EntitySerializer.url_for_model(user.profile),
    }

    with_hydro_publisher(GitHub.hydro_publisher) do
      assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
    end
  end

  test "Profile update publishes github.platform_health.v1.UserGeneratedContent when pronouns are updated" do
    GitHub.stubs(:hydro_enabled?).returns(true)

    user = create(:user)
    user.profile_pronouns = "she/her"
    user.save

    message = {
      request_context: nil,
      spamurai_form_signals: nil,
      action_type: :UPDATE,
      content_type: :PRONOUN,
      actor: Hydro::EntitySerializer.user(user),
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.ProfileUpdate"),
      content_database_id: user.profile.id,
      content_global_relay_id: user.profile.global_relay_id,
      content_created_at: user.profile.created_at,
      content_updated_at: user.profile.updated_at,
      title: Hydro::EntitySerializer.specimen_data(user.profile.name),
      content: Hydro::EntitySerializer.specimen_data(user.profile.pronouns),
      parent_content_author: nil,
      parent_content_database_id: nil,
      parent_content_global_relay_id: nil,
      parent_content_created_at: nil,
      parent_content_updated_at: nil,
      owner: Hydro::EntitySerializer.user(user),
      repository: nil,
      content_visibility: :PUBLIC,
      content_url: Hydro::EntitySerializer.url_for_model(user.profile),
    }

    with_hydro_publisher(GitHub.hydro_publisher) do
      assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
    end
  end

  test "instruments update and publishes to hydro, ignoring initial profile creation" do
    user = create(:user)
    user.profile_name = "donut"
    user.save

    GitHub.stubs(:hydro_enabled?).returns(true)

    assert_hydro_messages(count: 1, schema: "github.v1.ProfileUpdate")
  end

  test "has a user status" do
    user = create(:user)
    status = create(:user_status, user: user)
    profile = create(:profile, user: user)

    assert_equal status, profile.user_status
  end

  test "fails at database level when there are multiple profiles for a user" do
    user = create(:user)
    create(:profile, user: user)
    new_profile = build(:profile, user: user)

    assert_raises ActiveRecord::RecordNotUnique do
      new_profile.save!(validate: false)
    end
  end

  context "social_accounts" do
    test "returns an empty array when the encoded accounts are null" do
      profile = create(:profile)
      assert_nil profile.encoded_social_accounts
      assert_empty profile.social_accounts
    end

    test "sets and extracts encoded account data" do
      twitter_account = create(:social_account_twitter)
      mastodon_account = create(:social_account_mastodon)

      profile = create(:profile)
      profile.social_accounts = [twitter_account, mastodon_account]
      profile.save!
      refute_nil profile.encoded_social_accounts

      reloaded = Profile.find(profile.id)
      refute_nil reloaded.encoded_social_accounts
      assert_equal [twitter_account, mastodon_account], reloaded.social_accounts
    end

    test "enforces the validity of social accounts" do
      profile = create(:profile)
      profile.social_accounts = [
        create(:social_account_twitter, url: "https://example.com"),
        create(:social_account_mastodon),
        create(:social_account_linkedin, url: "https://twitter.com/monalisa"),
        create(:social_account, url: "https://#{'a' * SocialAccount::MAX_URL_LENGTH}.com")
      ]

      refute_predicate profile, :valid?

      assert_includes profile.errors[:encoded_social_accounts],
        "https://example.com is not a valid X profile URL"
      assert_includes profile.errors[:encoded_social_accounts],
        "https://twitter.com/monalisa is not a valid LinkedIn profile URL"
      assert_includes profile.errors[:encoded_social_accounts],
        "https://aaaaaaaaaaaa... is too long"
    end

    test "limits the number of social accounts" do
      profile = create(:profile)
      profile.social_accounts = create_list(:social_account, Profile::MAX_SOCIAL_ACCOUNTS + 1)

      refute_predicate profile, :valid?
      assert_includes profile.errors[:encoded_social_accounts], "cannot have more than 4 social accounts"
    end
  end

  context "twitter_url" do
    test "returns the URL from the first Twitter account associated with this profile" do
      profile = create(:profile, social_accounts: [
        create(:social_account_mastodon),
        create(:social_account_twitter, url: "https://twitter.com/monalisa"),
        create(:social_account_twitter, url: "https://twitter.com/notthisone"),
      ])

      assert_equal "https://twitter.com/monalisa", profile.twitter_url
    end

    test "returns nil if there are no Twitter accounts associated with this profile" do
      profile = create(:profile, social_accounts: [
        create(:social_account_youtube),
        create(:social_account_instagram),
      ])

      assert_nil profile.twitter_url
    end
  end

  context "twitter_username" do
    test "returns the username from the first Twitter account associated with this profile" do
      profile = create(:profile, social_accounts: [
        create(:social_account_mastodon),
        create(:social_account_twitter, url: "https://twitter.com/monalisa"),
        create(:social_account_twitter, url: "https://twitter.com/notthisone"),
      ])

      assert_equal "monalisa", profile.twitter_username
    end

    test "returns nil if there are no Twitter accounts associated with this profile" do
      profile = create(:profile, twitter_username: "ignoreme", social_accounts: [
        create(:social_account_youtube),
        create(:social_account_instagram),
      ])

      assert_nil profile.twitter_username
    end
  end

  context "twitter_username=" do
    test "when blank deletes all Twitter accounts" do
      mastodon_account = create(:social_account_mastodon)
      twitter0_account = create(:social_account_twitter)
      linkedin_account = create(:social_account_linkedin)
      twitter1_account = create(:social_account_twitter)
      profile = create(:profile, social_accounts: [
        mastodon_account,
        twitter0_account,
        linkedin_account,
        twitter1_account,
      ])

      profile.twitter_username = ""

      assert_equal [mastodon_account, linkedin_account], profile.social_accounts
    end

    test "updates the first pre-existing Twitter account" do
      mastodon_account = create(:social_account_mastodon)
      twitter0_account = create(:social_account_twitter, url: "https://twitter.com/first")
      linkedin_account = create(:social_account_linkedin)
      twitter1_account = create(:social_account_twitter, url: "https://twitter.com/second")
      profile = create(:profile, social_accounts: [
        mastodon_account,
        twitter0_account,
        linkedin_account,
        twitter1_account,
      ])

      profile.twitter_username = "incoming"

      changed_account = create(:social_account_twitter, url: "https://twitter.com/incoming")
      assert_equal [mastodon_account, changed_account, linkedin_account, twitter1_account], profile.social_accounts
    end

    test "adds a new Twitter account if none exist" do
      mastodon_account = create(:social_account_mastodon)
      linkedin_account = create(:social_account_linkedin)
      profile = create(:profile, social_accounts: [
        mastodon_account,
        linkedin_account,
      ])

      profile.twitter_username = "incoming"

      new_account = create(:social_account_twitter, url: "https://twitter.com/incoming")
      assert_equal [mastodon_account, linkedin_account, new_account], profile.social_accounts
    end

    test "does nothing when adding a new Twitter account but too many already exist" do
      profile = create(:profile, social_accounts: create_list(:social_account, Profile::MAX_SOCIAL_ACCOUNTS))

      profile.twitter_username = "incoming"

      assert_equal Profile::MAX_SOCIAL_ACCOUNTS, profile.social_accounts.size
      refute_includes profile.social_accounts.map(&:url), "https://twitter.com/incoming"
    end
  end

  if GitHub.sponsors_enabled?
    context "#alert_sponsors_listing_of_profile_change" do
      test "updates stafftools metadata with has_customized_user_profile=true without extra profile load" do
        sponsorable = create(:user)
        listing = create(:sponsors_listing, sponsorable: sponsorable)
        refute_predicate listing.stafftools_metadata, :has_customized_user_profile?

        assert_query_count_per_table({
          profiles: 2 # 1 SELECT + 1 INSERT
        }) do
          assert_no_query_warnings do
            create(:profile, user: sponsorable, name: "foo")
          end
        end

        assert_predicate listing.reload_stafftools_metadata, :has_customized_user_profile?
      end

      test "updates stafftools metadata with has_customized_user_profile=false without extra profile load" do
        sponsorable = create(:user)
        profile = create(:profile, user: sponsorable, bio: "I have customized my profile", name: nil,
          twitter_username: nil, blog: nil, company: nil)
        listing = create(:sponsors_listing, sponsorable: sponsorable)
        refute_nil profile.reload_sponsors_listing_stafftools_metadata
        assert_predicate listing.stafftools_metadata, :has_customized_user_profile?

        # 1 UPDATE
        assert_query_count_per_table({ profiles: 1 }) do
          assert_no_query_warnings do
            profile.update!(bio: nil)
          end
        end

        refute_predicate listing.reload_stafftools_metadata, :has_customized_user_profile?
      end
    end
  end

  test "target_for_conditional_acces returns the user" do
    profile = create(:profile)
    assert_equal profile.user, profile.target_for_conditional_access
  end
end
