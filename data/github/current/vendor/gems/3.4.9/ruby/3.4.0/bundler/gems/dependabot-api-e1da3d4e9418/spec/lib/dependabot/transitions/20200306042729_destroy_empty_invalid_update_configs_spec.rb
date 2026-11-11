# frozen_string_literal: true

require "rails_helper"

require_relative "../../../../lib/dependabot/transitions/20200306042729_destroy_empty_invalid_update_configs.rb"
RSpec.describe "DestroyEmptyInvalidUpdateConfigs" do
  let!(:repo) do
    FactoryBot.create(:repo)
  end
  let(:transition) do
    Dependabot::Transitions::DestroyEmptyInvalidUpdateConfigs.new(
      dry_run: false,
      limit: nil,
      offset: 0
    )
  end
  let(:dry_run_transition) do
    Dependabot::Transitions::DestroyEmptyInvalidUpdateConfigs.new(
      limit: nil,
      offset: 0
    )
  end
  let!(:first_duplicate_update_config) do
    FactoryBot.create(:update_config, :active, directory: "/tmp1", repo: repo)
  end
  let!(:second_duplicate_update_config) do
    FactoryBot.create(:update_config, :active, directory: "/tmp2", repo: repo)
  end
  let!(:inactive_update_config) do
    FactoryBot.create(:update_config, :deleted, repo: repo)
  end
  let!(:update_config_with_jobs) do
    FactoryBot.create(:update_config, :rate_limited,
                      directory: "/tmp3", repo: repo)
  end
  let!(:update_job) do
    FactoryBot.create(:update_job, update_config: update_config_with_jobs)
  end

  before do
    # Only active/rate_limited update configs require unique directory,
    # package_manager and target_branch
    second_duplicate_update_config.update_attribute(:directory, "/tmp1")
    update_config_with_jobs.update_attribute(:directory, "/tmp1")

    expect(first_duplicate_update_config).not_to be_valid
    expect(second_duplicate_update_config).not_to be_valid
    expect(inactive_update_config).to be_valid
    expect(update_config_with_jobs).not_to be_valid
  end

  context "write" do
    it "performs the transition" do
      expect(first_duplicate_update_config).to be_present
      expect(second_duplicate_update_config).to be_present

      transition.perform

      expect(inactive_update_config.reload).to be_present
      expect(update_config_with_jobs.reload).to be_present
      expect(
        UpdateConfig.find_by(id: first_duplicate_update_config.id)
      ).to be_nil
      expect(
        UpdateConfig.find_by(id: second_duplicate_update_config.id)
      ).to be_nil
    end
  end

  context "dry run" do
    it "does nothing on a dry run" do
      dry_run_transition.perform

      expect(inactive_update_config.reload).to be_present
      expect(update_config_with_jobs.reload).to be_present
      expect(first_duplicate_update_config.reload).to be_present
      expect(second_duplicate_update_config.reload).to be_present
    end
  end
end
