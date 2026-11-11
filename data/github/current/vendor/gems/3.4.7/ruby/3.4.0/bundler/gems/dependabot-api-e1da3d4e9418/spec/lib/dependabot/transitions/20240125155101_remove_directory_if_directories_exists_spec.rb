# frozen_string_literal: true

require "rails_helper"

require_relative "../../../../lib/dependabot/transitions/20240125155101_remove_directory_if_directories_exists.rb"
RSpec.describe Dependabot::Transitions::RemoveDirectoryIfDirectoriesExists do
  let(:transition) do
    described_class.new(dry_run: false)
  end

  let(:dry_run_transition) do
    described_class.new
  end

  before do
    create(:update_config, :active, directories: nil, directory: "/foo")
    create(:update_config, :active, directories: %w(/bar /foo), directory: nil)
    config = build(:update_config, :active, directories: %w(/bar /foo), directory: "/foo",
                                            required_instance_size: "small")
    config.save(validate: false)
  end

  context "write" do
    it "performs the transition" do
      expect(UpdateConfig.where.not(directory: nil).where.not(directories: nil).count).to eq(1)

      total = transition.perform

      expect(total).to eq(1)
      expect(UpdateConfig.where.not(directory: nil).where.not(directories: nil).count).to eq(0)
    end
  end

  context "dry run" do
    it "does nothing on a dry run" do
      expect(dry_run_transition.iterator.count).to eq(1)
      expect(UpdateConfig.where.not(directory: nil).where.not(directories: nil).count).to eq(1)

      total = dry_run_transition.perform

      expect(total).to eq(1)
      expect(dry_run_transition.iterator.count).to eq(1)
      expect(UpdateConfig.where.not(directory: nil).where.not(directories: nil).count).to eq(1)
    end
  end
end
