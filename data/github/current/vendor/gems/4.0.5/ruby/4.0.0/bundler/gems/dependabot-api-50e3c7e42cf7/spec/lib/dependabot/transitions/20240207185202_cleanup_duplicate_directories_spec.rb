# frozen_string_literal: true

require "rails_helper"

require_relative "../../../../lib/dependabot/transitions/20240207185202_cleanup_duplicate_directories.rb"
RSpec.describe Dependabot::Transitions::CleanupDuplicateDirectories do
  let(:transition) do
    described_class.new(dry_run: false)
  end

  let(:dry_run_transition) do
    described_class.new
  end

  before do
    repo = create(:repo, name: "repo2")
    create(:update_config, :active, repo: repo, directories: %w(/bar /foo), directory: nil,
                                    package_manager: "npm_and_yarn")
    create(:update_config, :active, repo: repo, directories: %w(/bar /foo), directory: nil, package_manager: "bundler")
    uc2 = create(:update_config, repo: repo, directories: %w(/bar /foo), directory: nil, package_manager: "bundler")
    uc2.transition_to!(:rate_limited, { validate: false })
  end

  context "write" do
    it "performs the transition" do
      expect(UpdateConfig.active.where.not(directories: nil).count).to eq(3)

      transition.perform

      expect(UpdateConfig.active.where.not(directories: nil).count).to eq(2)
    end
  end

  context "dry run" do
    it "does nothing on a dry run" do
      expect(UpdateConfig.active.where.not(directories: nil).count).to eq(3)

      dry_run_transition.perform

      expect(UpdateConfig.active.where.not(directories: nil).count).to eq(3)
    end
  end
end
