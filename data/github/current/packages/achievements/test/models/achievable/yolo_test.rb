# typed: true
# frozen_string_literal: true

require "test_helper"

class AchievableYoloTest < GitHub::TestCase
  context "#display_name" do
    test "it returns a custom overriden name for Achievable::Yolo" do
      yolo_achievable = create(:achievable, :yolo)

      display_name = yolo_achievable.display_name

      assert_equal "YOLO", display_name
    end
  end
end
