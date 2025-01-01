# typed: true
# frozen_string_literal: true

require "test_helper"

class BulkSponsorshipImportTest < GitHub::TestCase
  context "validations" do
    test "requires a sponsor" do
      import = BulkSponsorshipImport.new(sponsor_id: nil)
      refute_predicate import, :valid?
      assert_includes import.errors[:sponsor_id], "can't be blank"
    end

    test "requires data" do
      import = BulkSponsorshipImport.new(data: nil)
      refute_predicate import, :valid?
      assert_includes import.errors[:data], "can't be blank"
    end

    test "requires a unique sponsor" do
      sponsor = create(:user)
      import1 = create(:bulk_sponsorship_import, sponsor: sponsor)

      import2 = BulkSponsorshipImport.new(sponsor: sponsor)

      refute_predicate import2, :valid?
      assert_includes import2.errors[:sponsor_id], "has already been taken"
    end
  end

  context "#expired?" do
    test "returns false for new, unsaved import" do
      refute_predicate BulkSponsorshipImport.new, :expired?
    end

    test "returns true for import last updated over a day ago" do
      import = travel_to(25.hours.ago) { create(:bulk_sponsorship_import) }
      assert_predicate import, :expired?
    end

    test "returns false for import last updated within the last day" do
      import = travel_to(23.hours.ago) { create(:bulk_sponsorship_import) }
      refute_predicate import, :expired?
    end
  end
end
