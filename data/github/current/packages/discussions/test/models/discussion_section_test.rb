# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionSectionTest < GitHub::TestCase
  context "validations" do
    test "white space is stripped from name" do
      section = build(:discussion_section, name: "  name  ")

      section.validate

      assert_equal section.name, "name"
    end

    test "requires a present name" do
      section = build(:discussion_section, name: nil)
      refute_predicate section, :valid?
    end

    test "requires a name < 40 chars" do
      section = build(:discussion_section, name: "12345678901234567890123456789012345678901")
      refute_predicate section, :valid?
    end

    test "ensure valid utf8 in name and emoji" do
      %i[name emoji].each do |attr|
        section = build(:discussion_section, attr => "bad \x80 utf8")
        refute_predicate section, :valid?
      end
    end

    test "require a unique slug" do
      existing_with_slug = create(:discussion_section, name: "First section")
      section = build(
        :discussion_section,
        name: "first section",
        repository_id: existing_with_slug.repository_id
      )
      refute_predicate section, :valid?, "must be unique"
    end

    test "ensure no more than 25 sections are created" do
      repo = create(:repository)
      DiscussionSection::MAX_SECTIONS_PER_REPO.times { create(:discussion_section, repository: repo) }
      section = build(:discussion_section, repository: repo)
      refute_predicate section, :valid?, "cannot have more than 25 sections"
      assert_equal(
        section.errors[:repository].first,
        "can only have a maximum of #{DiscussionSection::MAX_SECTIONS_PER_REPO} sections"
      )
    end
  end

  context "emoji validations" do
    test "ensures that :emoji is a single, present, recognized emoji" do
      [":+1:", GRIN_EMOJI].each do |good|
        section = build(:discussion_section, emoji: good)
        assert_predicate section, :valid?, "did not accept #{good.inspect}"
      end

      [nil, "", ":one::two:", ":notes: extra text :notes:"].each do |bad|
        section = build :discussion_section, emoji: bad
        refute_predicate section, :valid?, "incorrectly accepted #{bad.inspect}"
      end
    end

    test "limits length of emoji" do
      max = GitHub::Validations::SingleEmojiValidator::EMOJI_MAX_LENGTH
      section = DiscussionSection.new(emoji: "a" * (max + 1))
      refute_predicate section, :valid?
      assert_equal "is too long (maximum is #{max} characters)", section.errors[:emoji].first
    end

    test "emoji field can hold long Unicode emoji" do
      emoji = "👩‍❤️‍💋‍👩"
      section = build(:discussion_section, emoji: emoji)
      assert_predicate section, :valid?
      assert section.save
      assert_equal emoji, section.reload.emoji
    end

    test "emoji field can hold long colon-style emoji" do
      emoji = ":south_georgia_south_sandwich_islands:"
      section = build(:discussion_section, emoji: emoji)
      assert_predicate section, :valid?
      assert section.save
      assert_equal emoji, section.reload.emoji
    end

    test "emoji field disallows more than one native emoji" do
      section = build(:discussion_section, emoji: "#{GRIN_EMOJI}#{GRIN_EMOJI}")
      refute_predicate section, :valid?
      assert_equal "can only be one emoji", section.errors[:emoji].first
    end

    test "emoji field disallows non-emoji text" do
      section = build(:discussion_section, emoji: ":chicken: hello")
      refute_predicate section, :valid?
      assert_equal "can only contain one supported emoji", section.errors[:emoji].first
    end

    test "emoji field requires a supported emoji" do
      section = build(:discussion_section, emoji: ":not-a-real-emoji:")
      refute_predicate section, :valid?
      assert_equal "does not contain a recognized emoji", section.errors[:emoji].first
    end

    test "emoji field cannot contain a custom image" do
      section = build(:discussion_section, emoji: %q(<img src="some-fake-emoji.png">))
      refute_predicate section, :valid?
      assert_equal "does not contain a recognized emoji", section.errors[:emoji].first
    end

    test "emoji field can contain a custom emoji" do
      section = build(:discussion_section, emoji: ":octocat:")
      assert_predicate section, :valid?
    end

    GitHub::Validations::AllowedEmojiValidator::BLOCKED_CUSTOM_EMOJI.each do |emoji_name|
      test "disallows #{emoji_name} colon-style emoji" do
        section = build(:discussion_section, emoji: ":#{emoji_name}:")
        refute_predicate section, :valid?
        assert_equal "contains an emoji that is not allowed", section.errors[:emoji].first
      end
    end

    GitHub::Validations::AllowedEmojiValidator::BLOCKED_NATIVE_EMOJI.each do |emoji_name|
      test "disallows #{emoji_name} colon-style emoji" do
        section = build(:discussion_section, emoji: ":#{emoji_name}:")
        refute_predicate section, :valid?
        assert_equal "contains an emoji that is not allowed", section.errors[:emoji].first
      end

      test "disallows #{emoji_name} Unicode emoji" do
        emoji = Emoji.find_by_alias(emoji_name)
        section = build(:discussion_section, emoji: emoji.raw)
        refute_predicate section, :valid?
        assert_equal "contains an emoji that is not allowed", section.errors[:emoji].first
      end
    end
  end
end
