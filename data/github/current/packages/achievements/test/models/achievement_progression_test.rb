# typed: true
# frozen_string_literal: true

require "test_helper"

class AchievementProgressionTest < GitHub::TestCase
  context "validations" do
    test "it validates the presence of the user" do
      progression = build(:pair_extraordinaire_achievement_progression, user: nil)

      progression.validate

      assert_includes progression.errors[:user], "can't be blank"
    end

    test "it validates the achievable slug is one of the known slugs" do
      progression = build(:yolo_achievement_progression, achievable_slug: "not-an-achievement")

      progression.validate

      assert_includes progression.errors[:achievable_slug], "is not included in the list"
    end

    test "it validates that a user can't have multiple achievement progresses with the same slug" do
      user = create(:user)
      create(:yolo_achievement_progression, user: user)
      progression = build(:yolo_achievement_progression, user: user)

      progression.validate

      assert_includes progression.errors[:achievable_slug], "has already been taken"
    end

    test "it validates the presence of an achievable slug" do
      progression = build(:yolo_achievement_progression, achievable_slug: nil)

      progression.validate

      assert_includes progression.errors[:achievable_slug], "can't be blank"
    end
  end

  context "#achievable" do
    test "it returns the proper achievable associated with the achievement" do
      progression = create(:pair_extraordinaire_achievement_progression)

      assert_instance_of Achievable::PairExtraordinaire, progression.achievable
    end
  end

  context "#to_h" do
    test "it returns the proper hash" do
      progression = create(:yolo_achievement_progression, public_count: 5, private_count: 10)

      assert_equal({ public_count: 5, private_count: 10 }, progression.to_h)
    end
  end

  context "#increment_count!" do
    test "it increments the public count" do
      progression = create(:yolo_achievement_progression, public_count: 7)

      progression.increment_count!(:PUBLIC)

      assert_equal 8, progression.public_count
    end

    test "it increments the private count" do
      progression = create(:yolo_achievement_progression, private_count: 17)

      progression.increment_count!(:PRIVATE)

      assert_equal 18, progression.private_count
    end

    test "it raises when the visibility is neither :PUBLIC nor :PRIVATE" do
      progression = create(:yolo_achievement_progression, public_count: 7, private_count: 17)

      assert_raises(ActiveModel::MissingAttributeError) { progression.increment_count!(:INVALID) }
      assert_equal 17, progression.reload.private_count
      assert_equal 7, progression.reload.public_count
    end
  end
end
