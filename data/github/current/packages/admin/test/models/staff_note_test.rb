# typed: true
# frozen_string_literal: true

require "test_helper"

class StaffNoteTest < GitHub::TestCase
  fixtures do
    @staffnote = create :staff_note
  end

  setup do
    User.create_ghost
  end

  context "#notable" do
    test "can be a User" do
      user = create :user
      note = create :staff_note, notable: user
      assert_equal user, note.notable
    end

    test "can be an Organization" do
      org = create :organization
      note = create :staff_note, notable: org
      assert_equal org, note.notable
    end

    test "can be a Business" do
      business = create :business
      note = create :staff_note, notable: business
      assert_equal business, note.notable
    end
  end

  context "#creator_name" do
    test "returns the user's name by default" do
      assert_equal @staffnote.user.name, @staffnote.creator_name
    end

    test "returns the ghost user's name when the user is deleted" do
      @staffnote.user.destroy
      @staffnote.reload
      assert_equal User.ghost.name, @staffnote.creator_name
    end
  end
end
