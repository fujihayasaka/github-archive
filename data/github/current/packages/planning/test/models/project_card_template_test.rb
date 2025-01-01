# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectCardTemplateTest < GitHub::TestCase
  test "initializes with required attributes" do
    card = ProjectCardTemplate.new(note: "Discuss: what type of cake should we have for dinner?")
    assert card.note
  end
end
