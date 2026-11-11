# frozen_string_literal: true

require "rails_helper"

require_relative "../../../../lib/dependabot/transitions/20240417143748_clean_directories.rb"
RSpec.describe Dependabot::Transitions::CleanDirectories do
  let(:transition) do
    described_class.new(dry_run: false)
  end

  let(:dry_run_transition) do
    described_class.new
  end

  before do
    [
      build(:update_config, :active, directories: %w(/foo /bar), directory: nil),
      build(:update_config, :active, directories: %w(/foo /bar /foo), directory: nil),
      build(:update_config, :active, directories: %w(/bar /foo), directory: nil),
    ].each do |config|
      config.required_instance_size = "small"
      config.save!(validate: false)
      config.transition_to!(:rate_limited)
    end
  end

  context "write" do
    it "performs the transition" do
      # setup or verify initial state

      transition.perform

      # check that the db has changed as expected
      expect(UpdateConfig.where(directories: %w(/bar /foo)).count).to eq(3)
    end
  end

  context "dry run" do
    it "does nothing on a dry run" do
      # setup or verify initial statedb

      dry_run_transition.perform

      # check that nothing has changed in the db
      expect(UpdateConfig.where(directories: %w(/bar /foo)).count).to eq(1)
    end
  end
end
