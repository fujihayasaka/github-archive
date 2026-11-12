# frozen_string_literal: true

require "rails_helper"

RSpec.describe SuggestedFix, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  subject(:suggested_fix) { FactoryBot.create(:suggested_fix) }

  describe "validations" do
    it { is_expected.to be_valid }

    describe "#autofix_suggestion_job" do
      it "is required" do
        suggested_fix.autofix_suggestion_job = nil
        expect(suggested_fix).not_to be_valid
      end

      it "validates uniqueness scoped to #autofix_suggestion_job" do
        first = create(:suggested_fix)
        second = build(:suggested_fix, autofix_suggestion_job: first.autofix_suggestion_job)

        expect(second).not_to be_valid
        expect(second.errors[:autofix_suggestion_job_id]).to include("has already been taken")
      end
    end

    describe "#review_status" do
      it "is required" do
        expect { FactoryBot.create(:suggested_fix, review_status: nil) }.to raise_error(ActiveRecord::RecordInvalid)

        expect { FactoryBot.create(:suggested_fix, review_status: "") }.to raise_error(ActiveRecord::RecordInvalid)
      end

      it "validates inclusion in review_statuses" do
        expect { FactoryBot.create(:suggested_fix, review_status: :invalid) }.to raise_error(ArgumentError)

        expect { FactoryBot.create(:suggested_fix, review_status: "invalid") }.to raise_error(ArgumentError)

        suggested_fix.review_status = :unreviewed
        expect(suggested_fix).to be_valid
      end
    end
  end
end
