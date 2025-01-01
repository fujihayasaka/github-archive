# typed: true
# frozen_string_literal: true

require "test_helper"

class UserLabelTest < GitHub::TestCase
  include StringFromBinaryTestHelper

  fixtures do
    @org = create :organization
    @user_label   = create :user_label, user: @org, color: "ff0000"
  end

  test "validates that user is an organization" do
    user_label = build(:user_label, user: create(:user))

    refute_predicate user_label, :valid?
    assert_includes user_label.errors.messages[:user], "must be an organization user"
  end

  test "sets lowercase_name from name on validation" do
    user_label = build(:user_label, name: "My Best Label")
    user_label.valid?
    assert_equal "my best label", user_label.lowercase_name
  end

  test "allows 4-byte unicode emoji in description field" do
    emoji = "Grin #{GRIN_EMOJI} Emoji"
    user_label = build(:user_label, description: emoji)

    assert_predicate user_label, :valid?
  end

  test "limits length of description field" do
    description = "a" * (Labelable::DESCRIPTION_MAX_LENGTH + 1)
    user_label = build(:user_label, description: description)

    refute_predicate user_label, :valid?
    assert_includes user_label.errors.messages[:description],
      "is too long (maximum is #{Labelable::DESCRIPTION_MAX_LENGTH} characters)"
  end

  test "limits length of name field" do
    name = "a" * (Labelable::NAME_MAX_LENGTH + 1)
    user_label = build(:user_label, name: name)

    refute_predicate user_label, :valid?
    assert_includes user_label.errors.messages[:name],
      "is too long (maximum is #{Labelable::NAME_MAX_LENGTH} characters)"
  end

  test "must have a six digit alnum color" do
    @user_label.color = "blaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaah!"
    refute_predicate @user_label, :valid?

    @user_label.color = "color=aaaaaa'};([],[][(![]+[]"
    refute_predicate @user_label, :valid?

    @user_label.color = "666666\nfoo"
    refute_predicate @user_label, :valid?

    @user_label.color = "666666\n"
    refute_predicate @user_label, :valid?

    @user_label.color = "666666"
    assert_predicate @user_label, :valid?

    @user_label.color = "c0c0c0"
    assert_predicate @user_label, :valid?
  end

  test "requires a name" do
    user_label = build(:user_label, name: "")

    refute_predicate user_label, :valid?
    assert_predicate user_label.errors[:name], :present?
  end

  test "requires case-insensitive uniqueness" do
    create(:user_label, name: "bugaboo", user: @org)
    user_label = build(:user_label, name: "BugABoo", user: @org)
    refute_predicate user_label, :valid?
    assert_predicate user_label.errors[:name], :present?
  end

  test "requires case-insensitive uniqueness, even with emoji" do
    create(:user_label, name: "bug #{GRIN_EMOJI}", user: @org)
    user_label = build(:user_label, name: "Bug #{GRIN_EMOJI}", user: @org)
    refute_predicate user_label, :valid?
    assert_predicate user_label.errors[:name], :present?
  end

  test "color shorthand is expanded on validation" do
    @user_label.color = "666"
    assert_predicate @user_label, :valid?
    assert_equal "666666", @user_label.color
  end

  test "strips leading and trailing whitespace from name" do
    @user_label.name = "  foo "
    assert_predicate @user_label, :valid?
    assert_equal "foo", @user_label.name
  end

  test "replaces newlines with spaces in name" do
    @user_label.name = "f\noo"
    assert_predicate @user_label, :valid?
    assert_equal "f oo", @user_label.name
  end

  test "strips leading and trailing whitespace from description" do
    @user_label.description = "  foo "

    assert_predicate @user_label, :valid?
    assert_equal "foo", @user_label.description
  end

  test "replaces newlines with spaces in description" do
    @user_label.description = "f\noo"

    assert_predicate @user_label, :valid?
    assert_equal "f oo", @user_label.description
  end

  test "doesn't accept non-hex 6-letter colors" do
    @user_label.color = "yellow"
    refute_predicate @user_label, :valid?
  end

  test "can't have commas" do
    @user_label.name = "blah,blah"
    refute_predicate @user_label, :valid?
  end

  test "can be alphanumericish" do
    @user_label.name = "ah-ha tékkub_likesPI 3.14"
    assert_predicate @user_label, :valid?
  end

  [:name, :lowercase_name].each do |field|
    test "supports emoji for #{field}" do
      encoded_value = "hey #{GRIN_EMOJI}"
      encoded_value2 = "hey \xF0\x9F\x98\x80"
      encoded_value3 = "hi 🙃".freeze

      if field == :lowercase_name
        user_label = create(:user_label, user: @org, name: encoded_value, lowercase_name: encoded_value)

        assert_multibyte_tracked_changes(user_label, field, encoded_value, encoded_value2, encoded_value3, :name)
      else
        user_label = create(:user_label, :user => @org, field => encoded_value)

        assert_multibyte_tracked_changes(user_label, field, encoded_value, encoded_value2)
      end
    end
  end

  test "supports UTF-8 for description using StringFromBinary" do
    user_label = create(:user_label, user: @org)
    user_label.reload

    assert_equal StringFromBinary.new, user_label.type_for_attribute(:description)
    assert_equal Encoding::UTF_8, user_label.description.encoding
  end

  test "cannot include only native emoji" do
    @user_label.name = GRIN_EMOJI

    refute_predicate @user_label, :valid?
    assert_includes @user_label.errors[:name], "must contain more than native emoji"
  end

  test "can be twitterish" do
    @user_label.name = "@defunkt"
    assert_predicate @user_label, :valid?
  end

  test "can be pipish" do
    @user_label.name = "|-| |"
    assert_predicate @user_label, :valid?
  end

  test "can be hashtaggish" do
    @user_label.name = "#realtalk"
    assert_predicate @user_label, :valid?
  end

  test "can contain unicode characters above 0xffff" do
    @user_label.name = "怎"
    assert_predicate @user_label, :valid?

    bell_emoji = [0x1F514].pack("U")
    @user_label.name = "#{bell_emoji} label"
    assert_predicate @user_label, :valid?
  end

  context "instrumentation for org-owned labels" do
    test "instrument_creation publishes an event" do
      events = subscribe "organization_default_label.create"

      user_label = create(:user_label, user: @org, name: "My Label")
      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        organization_default_label: "My Label",
        organization_default_label_id: user_label.id,
      }

      # Popping the most recent event from the subscription to "user.login".
      assert event = events.pop, "an event was expected"

      # Verifying the full shape of the event payload.
      assert_equal expected_payload, event.payload
    end
  end
end
