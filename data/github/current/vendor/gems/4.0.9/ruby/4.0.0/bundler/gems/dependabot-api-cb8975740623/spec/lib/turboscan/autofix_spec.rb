# frozen_string_literal: true

require "rails_helper"

RSpec.describe Turboscan::Autofix do
  describe "#generate_dependabot_fix" do
    # NOTE: The autofix experiment is no longer active so the turboscan-client gem has been removed because it blocked
    # upgrading to Ruby 3.4. So Turboscan::Autofix#generate_dependabot_fix now raises immediately.
    # The full autofix code still needs to get cleaned up at some point, including other references to Turboscan.
    it "raises because the autofix experiment is no longer active" do
      autofix_job = create(:autofix_suggestion_job)

      expect do
        described_class.new.generate_dependabot_fix(autofix_job)
      end.to raise_error(Turboscan::Autofix::Error, /no longer active/)
    end
  end
end
