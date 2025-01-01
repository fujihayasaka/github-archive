# typed: true
# frozen_string_literal: true

require "test_helper"

class StaffNotesDependencyTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @user = create :user
    @org = create :organization
    @business = create :business
  end

  context "#recent_staff_note?" do
    %i(user organization business).each do |notable_type|
      test "for #{notable_type} returns false by default when there is no note within past two years" do
        notable = create notable_type
        Timecop.freeze(3.years.ago) { create :staff_note, notable: notable }
        refute_predicate notable, :recent_staff_note?
      end

      test "for #{notable_type} returns true by default when there is a note within past two years" do
        notable = create notable_type
        create :staff_note, notable: notable
        assert_predicate notable, :recent_staff_note?
      end

      test "for #{notable_type} returns false when there is no note within the specified period" do
        notable = create notable_type
        Timecop.freeze(1.year.ago) { create :staff_note, notable: notable }
        refute notable.recent_staff_note?(2.months.ago)
      end

      test "for #{notable_type} returns true when there is a note within the specified period" do
        notable = create notable_type
        create :staff_note, notable: notable
        assert notable.recent_staff_note?(1.year.ago)
      end
    end
  end

  context "#pinned_staff_note?" do
    %i(user organization business).each do |notable_type|
      test "returns false when there is no pinned staff note for the #{notable_type}" do
        notable = create notable_type
        create :staff_note, notable: notable, is_pinned: false
        refute_predicate notable, :pinned_staff_note?
      end

      test "returns true when there is a pinned staff note for the #{notable_type}" do
        notable = create notable_type
        create :staff_note, notable: notable, is_pinned: false
        create :staff_note, notable: notable, is_pinned: true
        assert_predicate notable, :pinned_staff_note?
      end
    end
  end
end
