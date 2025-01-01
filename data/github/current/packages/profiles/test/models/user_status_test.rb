# typed: true
# frozen_string_literal: true

require "test_helper"

class UserStatusTest < GitHub::TestCase
  include HydroTestHelpers
  include GitHub::DatabaseQueryWarningsTestHelpers

  context "for_org scope" do
    test "includes statuses for the specified organization" do
      org1 = create(:organization)
      member1 = create(:user)
      org1.add_member(member1)
      org2 = create(:organization)
      member2 = create(:user)
      org2.add_member(member2)
      member3 = create(:user)
      org2.add_member(member3)
      status1 = create(:user_status)
      status2 = create(:user_status, user: member3, organization: org2)
      status3 = create(:user_status, user: member1, organization: org1)
      status4 = create(:user_status, user: member2, organization: org2)

      results = UserStatus.for_org(org2)

      refute_includes results, status1, "should not include public status"
      assert_includes results, status2
      refute_includes results, status3, "should not include status for different org"
      assert_includes results, status4
    end
  end

  context "for_org_or_public scope" do
    test "includes statuses for the specified organization" do
      org1 = create(:organization)
      member1 = create(:user)
      org1.add_member(member1)
      org2 = create(:organization)
      member2 = create(:user)
      org2.add_member(member2)
      member3 = create(:user)
      org2.add_member(member3)
      status1 = create(:user_status, user: member3, organization: org2)
      status2 = create(:user_status, user: member1, organization: org1)
      status3 = create(:user_status, user: member2, organization: org2)

      results = UserStatus.for_org_or_public(org2)

      assert_includes results, status1
      refute_includes results, status2, "should not include status for different org"
      assert_includes results, status3
    end

    test "includes public statuses" do
      org = create(:organization)
      member = create(:user)
      org.add_member(member)
      status1 = create(:user_status)
      status2 = create(:user_status, user: member, organization: org)

      results = UserStatus.for_org_or_public(org)

      assert_includes results, status1
      assert_includes results, status2
    end
  end

  context "active scope"  do
    test "includes active statuses" do
      user = create(:user)
      expired_user = create(:user)

      status = create(:user_status, user: user, expires_at: Time.current + 2.days)
      expired_status = create(:user_status, user: expired_user, expires_at: Time.current - 2.days)
      statuses = UserStatus.active

      assert_includes(statuses, status)
      refute_includes(statuses, expired_status)
    end

    test "includes statuses without an expiration" do
      user = create(:user)

      status = create(:user_status, user: user, expires_at: nil)
      statuses = UserStatus.active

      assert_includes(statuses, status)
    end
  end

  context "audit log" do
    test "instruments creating a user status" do
      user = create(:user)
      org = create(:organization)
      org.add_member(user)
      events = subscribe("user_status.update")

      assert_no_query_warnings do
        status = create(:user_status, user: user, emoji: GRIN_EMOJI, message: "what's up",
                        organization: org)

        expected_payload = {
          user: user.login,
          user_id: user.id,
          emoji: GRIN_EMOJI,
          message: "what's up",
          user_status: "#{GRIN_EMOJI} what's up",
          user_status_id: status.id,
          org: org.login,
          org_id: org.id,
          limited_availability: false,
          expires_at: nil,
        }
        refute_nil event = events.pop, "an event was expected"
        assert_equal "user_status.update", event.name
        assert_equal expected_payload, event.payload
      end
    end

    test "instruments updating a user status" do
      assert_no_query_warnings do
        user = create(:user)
        status = create(:user_status, user: user, emoji: GRIN_EMOJI, message: "what's up")
        events = subscribe("user_status.update")
        expected_payload = {
          user: user.login,
          user_id: user.id,
          emoji: ":heart:",
          message: "This is the new stuff.",
          user_status: ":heart: This is the new stuff.",
          user_status_id: status.id,
          org: nil,
          limited_availability: false,
          expires_at: nil,
        }

        status.message = "This is the new stuff."
        status.emoji = ":heart:"
        status.save!

        refute_nil event = events.pop, "an event was expected"
        assert_equal "user_status.update", event.name
        assert_equal expected_payload, event.payload
      end
    end

    test "instruments deleting a user status" do
      assert_no_query_warnings do
        user = create(:user)
        status = create(:user_status, user: user, emoji: GRIN_EMOJI, message: "what's up")
        events = subscribe("user_status.destroy")
        expected_payload = {
          user: user.login,
          user_id: user.id,
          emoji: GRIN_EMOJI,
          message: "what's up",
          user_status: "#{GRIN_EMOJI} what's up",
          user_status_id: status.id,
          org: nil,
          limited_availability: false,
          expires_at: nil,
        }

        status.destroy!

        refute_nil event = events.pop, "an event was expected"
        assert_equal "user_status.destroy", event.name
        assert_equal expected_payload, event.payload
      end
    end
  end

  context "#valid_emoji_and_message?" do
    test "true when given a valid emoji and message" do
      assert UserStatus.valid_emoji_and_message?(":smile:", "hey")
    end

    test "false when given an invalid emoji and valid message" do
      emoji = ":#{GitHub::Validations::AllowedEmojiValidator::BLOCKED_NATIVE_EMOJI.first}:"
      refute UserStatus.valid_emoji_and_message?(emoji, "hey")
    end

    test "true when given a valid emoji and no message" do
      assert UserStatus.valid_emoji_and_message?(":smile:", nil)
    end

    test "false when given a valid emoji and invalid message" do
      message = "a" * (UserStatus::MESSAGE_MAX_LENGTH + 1)
      refute UserStatus.valid_emoji_and_message?(GRIN_EMOJI, message)
    end

    test "true when given a valid message and no emoji" do
      assert UserStatus.valid_emoji_and_message?(nil, "hey")
    end

    test "false when given no emoji and no message" do
      refute UserStatus.valid_emoji_and_message?(nil, nil)
    end
  end

  context "#emoji_html" do
    test "converts native emoji to g-emoji tag" do
      status = build(:user_status, emoji: GRIN_EMOJI)
      assert_equal %Q(<div>#{GRIN_EMOJI}</div>),
        status.emoji_html
    end

    test "converts colon-style emoji to g-emoji tag" do
      status = build(:user_status, emoji: ":grinning:")
      assert_equal %Q(<div>#{GRIN_EMOJI}</div>),
        status.emoji_html
    end

    test "converts colon-style custom emoji to img tag" do
      status = build(:user_status, emoji: ":octocat:")
      assert_equal %Q(<div><img class="emoji" title=":octocat:" alt=":octocat:" src="#{GitHub.asset_host_url}/images/icons/emoji/octocat.png" height="20" width="20" align="absmiddle"></div>),
        status.emoji_html
    end

    test "returns nil when there is no emoji" do
      status = build(:user_status, emoji: nil)
      assert_nil status.emoji_html
    end
  end

  context "#message_html" do
    test "converts native emoji to g-emoji tag" do
      status = build(:user_status, message: GRIN_EMOJI)
      assert_equal %Q(<div>#{GRIN_EMOJI}</div>),
        status.message_html
    end

    test "converts colon-style emoji to g-emoji tag" do
      status = build(:user_status, message: ":grinning:")
      assert_equal %Q(<div>#{GRIN_EMOJI}</div>),
        status.message_html
    end

    test "links user mentions" do
      user = create(:user)
      status = build(:user_status, message: "hey @#{user}")
      assert_equal %Q(<div>hey <a class="user-mention notranslate" data-hovercard-type="user" data-hovercard-url="/users/#{user.login}/hovercard" data-octo-click="hovercard-link-click" data-octo-dimensions="link_type:self" href="#{GitHub.url}/#{user}">@#{user}</a></div>),
        status.message_html
    end

    test "links team mentions for an org-restricted status" do
      user = create(:user)
      org = create(:organization)
      org.add_member(user)
      team = create(:team, privacy: :closed, organization: org)
      assert team.visible_to?(user),
        "sanity check: we need the team visible to the user before they can mention it"
      status = build(:user_status, message: "hey @#{team.combined_slug}", organization: org,
                     user: user)
      team_path = "/orgs/#{org}/teams/#{team.to_param}"
      assert_equal %Q(<div>hey <a class="team-mention js-team-mention notranslate" data-error-text="Failed to load team members" data-id="#{team.id}" data-permission-text="Team members are private" data-url="#{team_path}/members" data-hovercard-type="team" data-hovercard-url="#{team_path}/hovercard" href="#{GitHub.url}#{team_path}">@#{team.combined_slug}</a></div>),
        status.message_html(viewer: user)
    end

    test "links organization mentions" do
      org = create(:organization)
      status = build(:user_status, message: "hey @#{org}")
      assert_equal_html %Q(<div>hey <a class=\"user-mention notranslate\" data-hovercard-type=\"organization\" data-hovercard-url=\"/orgs/#{org}/hovercard\" href=\"https://github.com/#{org}\" data-octo-click=\"hovercard-link-click\" data-octo-dimensions=\"link_type:self\" >@#{org}</a></div>),
        status.message_html
    end

    test "does not link mentions when link_mentions is false" do
      user = create(:user)
      org = create(:organization)
      org.add_member(user)
      team = create(:team, privacy: :closed, organization: org)
      other_member = create(:user)
      org.add_member(other_member)
      status = build(:user_status, message: "hey @#{team.combined_slug} @#{org} @#{other_member}",
                     organization: org, user: user)
      team_path = "/orgs/#{org}/teams/#{team.to_param}"
      assert_equal %Q(<div>hey @#{team.combined_slug} @#{org} @#{other_member}</div>),
        status.message_html(viewer: user, link_mentions: false)
    end

    test "returns nil when there is no message" do
      status = build(:user_status, message: nil)
      assert_nil status.message_html
    end
  end

  test "predefined statuses have valid emoji" do
    UserStatus::PREDEFINED_STATUSES.keys.each do |emoji_name|
      refute_nil Emoji.find_by_alias(emoji_name), "expected emoji #{emoji_name} to exist"
    end
  end

  context "validations" do
    test "requires user" do
      status = UserStatus.new
      refute_predicate status, :valid?
      assert_includes status.errors[:user], "can't be blank"
    end

    test "requires unique user" do
      status1 = create(:user_status)
      status2 = build(:user_status, user: status1.user)
      refute_predicate status2, :valid?
      assert_includes status2.errors[:user_id], "has already been taken"
    end

    test "requires an emoji or message" do
      user = create(:user)
      status = UserStatus.new(user: user)
      refute_predicate status, :valid?
      assert_includes status.errors[:base], "Either an emoji or a message is required."
    end

    test "does not require message" do
      user = create(:user)
      status = UserStatus.new(user: user, emoji: ":heart:")
      assert_predicate status, :valid?
    end

    test "does not require emoji" do
      user = create(:user)
      status = UserStatus.new(user: user, message: "my new status")
      assert_predicate status, :valid?
    end

    test "limits length of message" do
      status = UserStatus.new(message: "a" * (UserStatus::MESSAGE_MAX_LENGTH + 1))
      refute_predicate status, :valid?
      assert_equal "is too long (maximum is #{UserStatus::MESSAGE_MAX_LENGTH} characters)",
                   status.errors[:message].first
    end

    test "message field can hold long Unicode" do
      long_unicode_string = "Smooth sailing with Copilot #{GRIN_EMOJI}"
      status = build(:user_status, message: long_unicode_string)
      assert_predicate status, :valid?
      assert status.save
      assert_equal long_unicode_string, status.reload.message
    end

    test "limits length of emoji" do
      max = GitHub::Validations::SingleEmojiValidator::EMOJI_MAX_LENGTH
      status = UserStatus.new(emoji: "a" * (max + 1))
      refute_predicate status, :valid?
      assert_equal "is too long (maximum is #{max} characters)",
                   status.errors[:emoji].first
    end

    test "emoji field can hold long Unicode emoji" do
      emoji = "👩‍❤️‍💋‍👩"
      status = build(:user_status, emoji: emoji)
      assert_predicate status, :valid?
      assert status.save
      assert_equal emoji, status.reload.emoji
    end

    test "emoji field can hold long colon-style emoji" do
      emoji = ":south_georgia_south_sandwich_islands:"
      status = build(:user_status, emoji: emoji)
      assert_predicate status, :valid?
      assert status.save
      assert_equal emoji, status.reload.emoji
    end

    test "emoji field disallows more than one native emoji" do
      status = build(:user_status, emoji: "#{GRIN_EMOJI}#{GRIN_EMOJI}")
      refute_predicate status, :valid?
      assert_equal "can only be one emoji", status.errors[:emoji].first
    end

    # https://github.com/github/github/issues/109560
    test "emoji field disallows non-emoji text" do
      status = build(:user_status, emoji: ":chicken: hello")
      refute_predicate status, :valid?
      assert_equal "can only contain one supported emoji", status.errors[:emoji].first
    end

    test "emoji field requires a supported emoji" do
      status = build(:user_status, emoji: ":not-a-real-emoji:")
      refute_predicate status, :valid?
      assert_equal "does not contain a recognized emoji", status.errors[:emoji].first
    end

    test "emoji field cannot contain a custom image" do
      status = build(:user_status, emoji: %q(<img src="some-fake-emoji.png">))
      refute_predicate status, :valid?
      assert_equal "does not contain a recognized emoji", status.errors[:emoji].first
    end

    test "emoji field can contain a custom emoji" do
      status = build(:user_status, emoji: ":octocat:")
      assert_predicate status, :valid?
    end

    GitHub::Validations::AllowedEmojiValidator::BLOCKED_CUSTOM_EMOJI.each do |emoji_name|
      test "disallows #{emoji_name} colon-style emoji" do
        status = build(:user_status, emoji: ":#{emoji_name}:")
        refute_predicate status, :valid?
        assert_equal "contains an emoji that is not allowed", status.errors[:emoji].first
      end
    end

    GitHub::Validations::AllowedEmojiValidator::BLOCKED_NATIVE_EMOJI.each do |emoji_name|
      test "disallows #{emoji_name} colon-style emoji" do
        status = build(:user_status, emoji: ":#{emoji_name}:")
        refute_predicate status, :valid?
        assert_equal "contains an emoji that is not allowed", status.errors[:emoji].first
      end

      test "disallows #{emoji_name} Unicode emoji" do
        emoji = Emoji.find_by_alias(emoji_name)
        status = build(:user_status, emoji: emoji.raw)
        refute_predicate status, :valid?
        assert_equal "contains an emoji that is not allowed", status.errors[:emoji].first
      end
    end

    test "disallows organization to which the user doesn't belong" do
      org = create(:organization)
      user = create(:user)
      status = build(:user_status, user: user, organization: org)
      refute_predicate status, :valid?
      assert_equal "must be an organization #{user} belongs to", status.errors[:organization].first
    end
  end

  test "Hydro event is logged when creating a new status" do
    GitHub.stubs(:hydro_enabled?).returns(true)
    user = create(:user)

    status = create(:user_status, :with_expiration, user: user)

    message = {
      user: Hydro::EntitySerializer.user(user),
      message: status.message,
      emoji: status.emoji,
      new_status: Hydro::EntitySerializer.user_status(status),
    }
    assert_hydro_published(message, schema: "github.v1.UserStatusChange")
  end

  test "Hydro event is logged when updating an existing status" do
    user = create(:user)
    status = create(:user_status, user: user)
    GitHub.stubs(:hydro_enabled?).returns(true)

    status.message = "A brand new message"
    status.emoji = ":heart:"
    status.expires_at = 3.days.from_now
    status.save

    message = {
      user: Hydro::EntitySerializer.user(user),
      message: "A brand new message",
      emoji: ":heart:",
      new_status: Hydro::EntitySerializer.user_status(status),
    }

    assert_hydro_published(message, schema: "github.v1.UserStatusChange")
  end

  test "Hydro event is logged when deleting a status" do
    user = create(:user)
    status = create(:user_status, user: user)
    GitHub.stubs(:hydro_enabled?).returns(true)

    status.destroy

    message = {
      user: Hydro::EntitySerializer.user(user),
      message: nil,
      emoji: nil,
      new_status: Hydro::EntitySerializer.user_status(status),
    }
    assert_hydro_published(message, schema: "github.v1.UserStatusChange")
  end

  context ".set_for" do
    test "deletes existing status for user when given nils" do
      status = create(:user_status)

      assert_difference "UserStatus.count", -1 do
        assert_nil UserStatus.set_for(status.user, emoji: nil, message: nil),
          "#set_for should have returned nil"

        refute UserStatus.exists?(status.id)
      end
    end

    test "creates an audit log" do
      user = create(:user)
      events = subscribe("user_status.update")

      status = UserStatus.set_for(user, emoji: ":grinning:", message: "Drinking a mocha")

      expected_payload = {
        user: user.login,
        user_id: user.id,
        emoji: ":grinning:",
        message: "Drinking a mocha",
        user_status: ":grinning: Drinking a mocha",
        user_status_id: status.id,
        org: nil,
        limited_availability: false,
        expires_at: nil,
      }
      refute_nil event = events.pop, "an event was expected"
      assert_equal "user_status.update", event.name
      assert_equal expected_payload, event.payload
    end

    test "logs a Hydro event" do
      user = create(:user)
      GitHub.stubs(:hydro_enabled?).returns(true)

      status = UserStatus.set_for(user, emoji: ":grinning:", message: "Drinking a mocha")

      message = {
        user: Hydro::EntitySerializer.user(user),
        message: "Drinking a mocha",
        emoji: ":grinning:",
        new_status: Hydro::EntitySerializer.user_status(status),
      }
      assert_hydro_published(message, schema: "github.v1.UserStatusChange")
    end

    test "creates status with an emoji and a message for user when none exists" do
      user = create(:user)

      assert_difference "UserStatus.count" do
        status = UserStatus.set_for(user, emoji: ":grinning:", message: "#pairingwithmike")

        refute_nil status
        assert_equal ":grinning:", status.emoji
        assert_equal "#pairingwithmike", status.message
      end
    end

    test "creates status with a particular organization" do
      user = create(:user)
      org = create(:organization)
      org.add_member(user)

      assert_difference "UserStatus.count" do
        status = UserStatus.set_for(user, emoji: ":grinning:", message: "hey there", org: org)

        refute_nil status
        assert_equal ":grinning:", status.emoji
        assert_equal "hey there", status.message
        assert_equal org, status.organization
      end
    end

    test "creates status with just a message for user when none exists" do
      user = create(:user)

      assert_difference "UserStatus.count" do
        status = UserStatus.set_for(user, emoji: nil, message: "testing pls ignore")

        refute_nil status
        assert_nil status.emoji
        assert_equal "testing pls ignore", status.message
      end
    end

    test "creates status with an expiration date if expires_at is set" do
      user = create(:user)

      assert_difference "UserStatus.count" do
        Timecop.freeze do
          expires_at = 1.week.ago
          status = UserStatus.set_for(user, emoji: ":grinning:", message: "hey there", expires_at: expires_at)

          refute_nil status
          assert_equal ":grinning:", status.emoji
          assert_equal "hey there", status.message
          assert_in_delta expires_at, status.expires_at, 1
        end
      end
    end

    test "updates existing status for user" do
      user = create(:user)
      status = Timecop.freeze(1.week.ago) { create(:user_status, user: user) }
      old_updated_at = status.updated_at
      old_created_at = status.created_at

      assert_no_difference "UserStatus.count" do
        status = UserStatus.set_for(user, emoji: GRIN_EMOJI, message: "Hello World")

        refute_nil status
        assert_equal GRIN_EMOJI, status.emoji
        assert_equal "Hello World", status.message
        refute_equal old_updated_at, status.updated_at
        assert_equal old_created_at, status.created_at
      end
    end

    test "updates existing status organization for user" do
      user = create(:user)
      org1 = create(:organization)
      org1.add_member(user)
      org2 = create(:organization)
      org2.add_member(user)
      status = Timecop.freeze(1.week.ago) { create(:user_status, user: user, organization: org1) }
      old_updated_at = status.updated_at
      old_created_at = status.created_at

      assert_no_difference "UserStatus.count" do
        status = UserStatus.set_for(user, emoji: GRIN_EMOJI, message: "Hello World", org: org2)

        refute_nil status
        assert_equal GRIN_EMOJI, status.emoji
        assert_equal "Hello World", status.message
        refute_equal old_updated_at, status.updated_at
        assert_equal old_created_at, status.created_at
        assert_equal org2, status.organization
      end
    end

    test "returns nil when invalid message is given and user has no status already" do
      user = create(:user)
      message = "a" * (UserStatus::MESSAGE_MAX_LENGTH + 1)

      assert_no_difference "UserStatus.count" do
        status = UserStatus.set_for(user, emoji: GRIN_EMOJI, message: message)
        assert_nil status
      end
    end

    test "returns existing status when invalid message is given" do
      user = create(:user)
      existing_status = create(:user_status, user: user)
      message = "a" * (UserStatus::MESSAGE_MAX_LENGTH + 1)

      assert_no_difference "UserStatus.count" do
        status = UserStatus.set_for(user, emoji: GRIN_EMOJI, message: message)
        assert_equal existing_status, status
      end
    end

    test "returns nil when invalid emoji is given and user has no status already" do
      user = create(:user)
      emoji = ":#{GitHub::Validations::AllowedEmojiValidator::BLOCKED_NATIVE_EMOJI.first}:"

      assert_no_difference "UserStatus.count" do
        status = UserStatus.set_for(user, emoji: emoji, message: "hey")
        assert_nil status
      end
    end

    test "returns existing status when invalid emoji is given" do
      user = create(:user)
      existing_status = create(:user_status, user: user)
      emoji = ":#{GitHub::Validations::AllowedEmojiValidator::BLOCKED_CUSTOM_EMOJI.first}:"

      assert_no_difference "UserStatus.count" do
        status = UserStatus.set_for(user, emoji: emoji, message: "hey")
        assert_equal existing_status, status
      end
    end

    test "will not set your status for an organization to which you don't belong" do
      user = create(:user)
      org = create(:organization)
      create(:user_status, user: user)

      status = UserStatus.set_for(user, org: org, message: "new message", emoji: nil)

      refute_nil status
      refute_equal org, status.organization
      assert_equal user, status.user
      assert_equal "new message", status.message
      assert_nil status.emoji
    end
  end

  context "#async_readable_by?" do
    test "true when user status belongs to the viewer" do
      status = create(:user_status)
      assert status.async_readable_by?(status.user).sync
    end

    test "true for a global status when viewed anonymously" do
      status = create(:user_status)
      assert status.async_readable_by?(nil).sync
    end

    if GitHub.spamminess_check_enabled?
      test "false for anonymous viewer when user status belongs to a spammy user" do
        spammer = create(:spammy_user)
        status = create(:user_status, user: spammer)
        refute status.async_readable_by?(nil).sync
      end
    end

    test "false when an anonymous viewer views an organization-specific status" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      status = create(:user_status, user: user, organization: org)
      refute status.async_readable_by?(nil).sync
    end

    test "false when a non-member viewer views an organization-specific status" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      rando = create(:user)
      status = create(:user_status, user: user, organization: org)
      refute status.async_readable_by?(rando).sync
    end

    test "true when a fellow org member views an organization-specific status" do
      org = create(:organization)
      user = create(:user)
      user2 = create(:user)
      org.add_member(user)
      org.add_member(user2)
      status = create(:user_status, user: user, organization: org)
      assert status.async_readable_by?(user2).sync
    end
  end

  context "#expired?" do
    test "false when expires_at is nil" do
      status = create(:user_status, expires_at: nil)

      refute_predicate status, :expired?
    end

    test "false when expires_at is in the future from the current date" do
      status = create(:user_status, expires_at: 5.days.from_now)

      refute_predicate status, :expired?
    end

    test "false when expires at is in the future but in a different time zone" do
      current_time = Time.current
      expire_time = 1.hour.from_now
      status = create(:user_status, expires_at: expire_time.in_time_zone("Pacific Time (US & Canada)"))

      Timecop.freeze(current_time.in_time_zone("Eastern Time (US & Canada)")) do
        refute_predicate status, :expired?
      end
    end

    test "true when expires_at is in the past from the current date" do
      status = create(:user_status, expires_at: 5.days.ago)

      assert_predicate status, :expired?
    end

    test "true when expires_at is past the current date UTC in a different timezone" do
      expired_time = 1.hour.from_now.in_time_zone("Eastern Time (US & Canada)")
      status = create(:user_status, expires_at: expired_time)

      Timecop.freeze(2.hours.from_now.in_time_zone("Pacific Time (US & Canada)")) do
        assert_predicate status, :expired?
      end
    end
  end
end
