# frozen_string_literal: true

require "rails_helper"
require "dependabot/cronjob_validator"

RSpec.describe Dependabot::CronjobValidator do
  describe "validate_cronjob_expression" do
    it "does not raise for a valid cron expression" do
      expect { described_class.validate_cronjob_expression("0 12 * * *") }.not_to raise_error
    end

    it "raises InvalidCronjobExpressionError for an invalid cron expression" do
      expect { described_class.validate_cronjob_expression("invalid") }.
        to raise_error(described_class::InvalidCronjobExpressionError, /Invalid cronjob expression/)
    end

    it "raises InvalidCronjobExpressionError when cron expression includes a timezone" do
      expect { described_class.validate_cronjob_expression("0 12 * * * America/New_York") }.
        to raise_error(described_class::InvalidCronjobExpressionError, /must not include a timezone/)
    end

    it "raises InvalidCronjobExpressionError when cron expression includes UTC timezone" do
      expect { described_class.validate_cronjob_expression("0 12 * * * UTC") }.
        to raise_error(described_class::InvalidCronjobExpressionError, /must not include a timezone/)
    end

    it "raises InvalidCronjobExpressionError when interval is less than minimum allowed" do
      expect { described_class.validate_cronjob_expression("0 */12 * * *") }. # every 12 hours
        to raise_error(described_class::InvalidCronjobExpressionError, /less than the minimum allowed interval/)
    end

    it "raises InvalidCronjobExpressionError when interval exceeds maximum allowed" do
      # Run on Feb 29 (leap year only - every 4 years)
      expect { described_class.validate_cronjob_expression("0 0 29 2 *") }.
        to raise_error(described_class::InvalidCronjobExpressionError, /greater than the maximum allowed interval/)
    end
  end

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

    it "returns false when the parsed object does not respond to hours" do
      cronjob_exp = "@tomorrow"
      local_time = Time.utc(2023, 10, 1, 12, 0)

      expect(described_class.cronjob_match?(cronjob_exp, local_time)).to be false
    end
  end
end
