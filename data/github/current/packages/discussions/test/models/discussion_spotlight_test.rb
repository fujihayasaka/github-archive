# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionSpotlightTest < GitHub::TestCase
  include HydroTestHelpers

  context "validations" do
    test "validates discussion is unique per repo" do
      spotlight = create(:discussion_spotlight)

      duplicate_spotlight = build(
        :discussion_spotlight,
        discussion: spotlight.discussion,
      )
      refute_predicate duplicate_spotlight, :valid?
      refute_empty duplicate_spotlight.errors[:discussion]

      spotlight_for_different_repo = build(
        :discussion_spotlight,
        repository: create(:repository, has_discussions: true),
      )
      assert_predicate spotlight_for_different_repo, :valid?
      assert_empty spotlight_for_different_repo.errors[:discussion_id]
    end

    test "must have a six digit alphanumeric color" do
      spotlight = build(:discussion_spotlight, custom_color: "blaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaah!")
      refute_predicate spotlight, :valid?

      spotlight = build(:discussion_spotlight, custom_color: "color=aaaaaa'};([],[][(![]+[]")
      refute_predicate spotlight, :valid?

      spotlight = build(:discussion_spotlight, custom_color: "666666\nfoo")
      refute_predicate spotlight, :valid?

      spotlight = build(:discussion_spotlight, custom_color: "666666\n")
      refute_predicate spotlight, :valid?

      spotlight = build(:discussion_spotlight, custom_color: "666666")
      assert_predicate spotlight, :valid?

      spotlight = build(:discussion_spotlight, custom_color: "c0c0c0")
      assert_predicate spotlight, :valid?
    end

    test "doesn't accept non-hex 6-letter custom colors" do
      spotlight = build(:discussion_spotlight, custom_color: "yellow")
      refute_predicate spotlight, :valid?
    end

    test "color shorthand is expanded on validation" do
      spotlight = DiscussionSpotlight.new(custom_color: "666")
      spotlight.valid?
      assert_equal "666666", spotlight.custom_color
    end

    test "requires a preconfigured color or a custom color" do
      spotlight = build(:discussion_spotlight, preconfigured_color: nil,
        custom_color: nil)
      refute_predicate spotlight, :valid?
      assert_includes spotlight.errors[:base],
        "Either a preconfigured color or a custom color must be set."
    end

    test "requires a repository" do
      spotlight = DiscussionSpotlight.new
      refute_predicate spotlight, :valid?
      assert_includes spotlight.errors[:repository], "must exist"
    end

    test "requires spotlighted_by on create" do
      spotlight = DiscussionSpotlight.new
      refute_predicate spotlight, :valid?
      assert_includes spotlight.errors[:spotlighted_by], "can't be blank"
    end

    test "allows a nil spotlighted_by on update" do
      spotlight = create(:discussion_spotlight)
      spotlight.spotlighted_by = nil
      assert_predicate spotlight, :valid?
    end

    test "requires discussion" do
      spotlight = DiscussionSpotlight.new
      refute_predicate spotlight, :valid?
      assert_includes spotlight.errors[:discussion], "must exist"
    end

    test "disallows multiple spotlights for the same discussion" do
      existing_spotlight = create(:discussion_spotlight)
      new_spotlight = build(:discussion_spotlight, discussion: existing_spotlight.discussion)
      refute_predicate new_spotlight, :valid?
      assert_equal "has already been taken", new_spotlight.errors[:discussion].first
    end

    test "requires a unique position in the repository" do
      spotlight1 = create(:discussion_spotlight)
      spotlight2 = create(:discussion_spotlight, repository: spotlight1.repository)

      spotlight2.position = spotlight1.position

      refute_predicate spotlight2, :valid?
      assert_equal "has already been taken", spotlight2.errors[:position].first
    end

    test "limits how many spotlights are allowed per repository" do
      repo = create(:repository, has_discussions: true)
      DiscussionSpotlight::LIMIT_PER_REPOSITORY.times do
        create(:discussion_spotlight, repository: repo)
      end
      spotlight = build(:discussion_spotlight, repository: repo)
      refute_predicate spotlight, :valid?
      assert_includes spotlight.errors.full_messages,
        "Total discussion spotlights for your repository must be less than " \
        "#{DiscussionSpotlight::LIMIT_PER_REPOSITORY}"
    end
  end

  context "#preconfigured_color_names" do
    test "returns subset of colors" do
      color_names = DiscussionSpotlight.preconfigured_color_names

      assert_equal color_names, DiscussionSpotlight::NEXT_PRECONFIGURED_COLORS
    end
  end

  context "#api_preconfigured_color" do
    test "returns the corresponding next color name for each legacy color name" do
      spotlight = build(:discussion_spotlight)

      %i[peach_red orange_magenta gold_red].each do |color|
        spotlight.update(preconfigured_color: color)
        assert_equal "red_orange", spotlight.api_preconfigured_color, "mismatch for preconfigured color #{color}"
      end

      %i[green teal].each do |color|
        spotlight.update(preconfigured_color: color)
        assert_equal "blue_mint", spotlight.api_preconfigured_color, "mismatch for preconfigured color #{color}"
      end

      %i[cyan_purple periwinkle_navy purple_navy].each do |color|
        spotlight.update(preconfigured_color: color)
        assert_equal "blue_purple", spotlight.api_preconfigured_color, "mismatch for preconfigured color #{color}"
      end

      %i[purple salmon_purple].each do |color|
        spotlight.update(preconfigured_color: color)
        assert_equal "pink_blue", spotlight.api_preconfigured_color, "mismatch for preconfigured color #{color}"
      end

      %i[fuchsia_purple gray].each do |color|
        spotlight.update(preconfigured_color: color)
        assert_equal "purple_coral", spotlight.api_preconfigured_color, "mismatch for preconfigured color #{color}"
      end
    end
  end

  context "#color_stops" do
    test "it returns the new mapped color" do
      spotlight = create(:discussion_spotlight, preconfigured_color: :periwinkle_navy)

      color_stops = spotlight.color_stops

      assert_equal color_stops, DiscussionSpotlight::NEXT_PRECONFIGURED_COLOR_STOPS[:periwinkle_navy]
    end
  end

  test "sets position on create" do
    first_spotlight = create(:discussion_spotlight)
    assert_equal 1, first_spotlight.position

    second_spotlight = create(:discussion_spotlight, repository: first_spotlight.repository)
    assert_equal 2, second_spotlight.position
  end

  # https://github.com/github/discussions/issues/786
  test "doesn't assume max position to be the count of spotlights" do
    repo = create(:repository, has_discussions: true)
    first_spotlight, second_spotlight = create_pair(:discussion_spotlight, repository: repo)
    first_spotlight.destroy

    third_spotlight = create(:discussion_spotlight, repository: repo)
    assert_equal 3, third_spotlight.position
  end

  context "Hydro events", skip_enterprise: true do
    test "logs discussion pin event on creation" do
      spotlight = create(:discussion_spotlight)

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(spotlight.spotlighted_by),
        discussion: Hydro::EntitySerializer.discussion(spotlight.discussion),
        category: Hydro::EntitySerializer.discussion_category(spotlight.discussion.category),
        repository: Hydro::EntitySerializer.repository(spotlight.discussion.repository),
        repository_owner: Hydro::EntitySerializer.user(spotlight.discussion.repository.owner),
      }

      assert_hydro_published(message, schema: "github.discussions.v1.DiscussionPin")
      assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionPin")
    end

    test "logs discussion unpin event on deletion" do
      actor = create(:user)
      spotlight = create(:discussion_spotlight)

      spotlight.actor = actor
      spotlight.destroy

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(actor),
        discussion: Hydro::EntitySerializer.discussion(spotlight.discussion),
        category: Hydro::EntitySerializer.discussion_category(spotlight.discussion.category),
        repository: Hydro::EntitySerializer.repository(spotlight.discussion.repository),
        repository_owner: Hydro::EntitySerializer.user(spotlight.discussion.repository.owner),
      }

      assert_hydro_published(message, schema: "github.discussions.v1.DiscussionUnpin")
      assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionUnpin")
    end
  end
end
