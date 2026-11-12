# frozen_string_literal: true

require "rails_helper"

require_relative "../../../../lib/dependabot/transitions/20240108155722_remove_incorrect_directories.rb"
RSpec.describe Dependabot::Transitions::RemoveIncorrectDirectories do
  let(:transition) do
    described_class.new(dry_run: false)
  end

  let(:dry_run_transition) do
    described_class.new
  end

  before do
    create(:update_config, :active, directory: nil, directories: %w(bar foo))
    create(:update_config, :active, directory: nil, directories: %w(bar foo), update_schedule: "never")
  end

  context "write" do
    it "performs the transition" do
      expect(transition.iterator.count).to eq(1)

      transition.perform

      expect(transition.iterator.count).to eq(0)
    end
  end

  context "dry run" do
    it "does nothing on a dry run" do
      expect(dry_run_transition.iterator.count).to eq(1)

      dry_run_transition.perform

      expect(dry_run_transition.iterator.count).to eq(1)
    end
  end
end
