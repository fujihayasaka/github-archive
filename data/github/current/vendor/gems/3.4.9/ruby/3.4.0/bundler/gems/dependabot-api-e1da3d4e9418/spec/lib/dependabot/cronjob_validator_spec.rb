# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dependabot::CronjobValidator do
  describe "cronjob_match?" do
    it "returns true for a cronjob that matches the local time" do
      cronjob_exp = "0 12 * * *" # Every day at 12:00 PM
      local_time = Time.utc(2023, 10, 1, 12, 0) # UTC time for 12:00 PM

      expect(described_class.cronjob_match?(cronjob_exp, local_time)).to be true
    end

    it "returns false for a cronjob that does not match the local time" do
      cronjob_exp = "0 12 * * *" # Every day at 12:00 PM
      local_time = Time.utc(2023, 10, 1, 11, 0) # UTC time for 11:00 AM

      expect(described_class.cronjob_match?(cronjob_exp, local_time)).to be false
    end

    it "returns false when the schedule is too frequent" do
      cronjob_exp = "@hourly"
      local_time = Time.utc(2023, 10, 1, 0, 0) # UTC time for 12:00 AM

      expect(described_class.cronjob_match?(cronjob_exp, local_time)).to be false
    end
  end
end
