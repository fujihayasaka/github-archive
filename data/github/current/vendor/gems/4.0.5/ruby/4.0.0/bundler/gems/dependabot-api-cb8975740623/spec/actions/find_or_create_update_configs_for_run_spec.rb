# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindOrCreateUpdateConfigsForRun do
  subject(:action) do
    described_class.new(repo:, package_manager:, directories:, user:)
  end

  let(:repo) { create(:repo) }
  let(:package_manager) { "bundler" }
  let(:user) do
    HydroHandlers::GitHub::User.new({
                                      id: 1,
                                      login: "github",
                                      type: "Organization",
                                      tenant_id: 1,
                                      tenant_slug: "github",
                                    },
                                    installation_id: 7)
  end

  describe "#run" do
    subject(:run) { action.run }

    context "when there are existing user-defined UpdateConfigs covering all directories" do
      let!(:foo) do
        create(:update_config, :active, repo:, package_manager:, directory: nil, directories: ["/foo"])
      end
      let!(:bar) do
        create(:update_config, :active, repo:, package_manager:, directory: nil, directories: ["/bar"])
      end
      let(:directories) { ["/foo", "/bar"] }

      it "returns the existing UpdateConfigs" do
        expect(UpdateConfig.count).to eq(2)
        expect(run).to eq({
                            foo => ["/foo"],
                            bar => ["/bar"],
                          })
        expect(UpdateConfig.count).to eq(2)
      end
    end

    context "when there are existing user-defined UpdateConfigs covering some directories" do
      let!(:foo) do
        create(:update_config, :active, repo:, package_manager:, directory: nil, directories: ["/foo"])
      end
      let(:directories) { ["/foo", "/bar"] }

      it "returns the existing UpdateConfigs and creates new ones as needed" do
        expect { run }.to change(UpdateConfig, :count).by(1)
        expect(run).to eq({
                            foo => ["/foo"],
                            UpdateConfig.last => ["/bar"],
                          })
        expect(UpdateConfig.last).to have_attributes(directories: ["/bar"])
      end
    end

    context "when there are no existing user-defined UpdateConfigs" do
      let(:directories) { ["/foo", "/bar"] }

      it "creates one new UpdateConfig" do
        expect { run }.to change(UpdateConfig, :count).by(1)
        expect(run).to eq({
                            UpdateConfig.last => ["/foo", "/bar"],
                          })
        expect(UpdateConfig.last).to have_attributes(directories: ["/bar", "/foo"])
      end
    end

    context "when there is an ephemeral UpdateConfig covering some directories" do
      let!(:foo) do
        create(:update_config, :active, update_schedule: "never", repo:, package_manager:, directory: nil,
                                        directories: ["/foo"])
      end
      let(:directories) { ["/foo", "/bar"] }

      it "reuses the ephemeral UpdateConfig but returns all directories" do
        expect(run).to eq({
                            foo => ["/bar", "/foo"],
                          })
      end
    end

    context "when there is an ephemeral UpdateConfig covering all directories" do
      let!(:all) do
        create(:update_config, :active, update_schedule: "never", repo:, package_manager:, directory: nil,
                                        directories: ["/bar", "/foo"])
      end
      let(:directories) { ["/foo", "/bar"] }

      it "reuses the ephemeral UpdateConfig" do
        expect(run).to eq({
                            all => ["/bar", "/foo"],
                          })
      end
    end

    context "when there is an ephemeral UpdateConfig covering no directories" do
      let!(:foo) do
        create(:update_config, :active, update_schedule: "never", repo:, package_manager:, directory: nil,
                                        directories: ["/foo"])
      end
      let(:directories) { ["/bar"] }

      it "reuses the ephemeral UpdateConfig" do
        expect(run).to eq({
                            foo => ["/bar"],
                          })
      end
    end

    context "when there is a user-defined UpdateConfig covering no directories" do
      let(:directories) { ["/bar"] }

      it "creates an ephemeral config for the missing directory" do
        create(:update_config, :active, repo:, package_manager:, directory: nil, directories: ["/foo"])

        expect { run }.to change(UpdateConfig, :count).by(1)
        expect(run).to eq({
                            UpdateConfig.last => ["/bar"],
                          })
      end
    end

    context "when target_branch is provided" do
      subject(:action) do
        described_class.new(repo:, package_manager:, directories:, user:, target_branch: "feature-branch")
      end

      let(:directories) { ["/"] }

      it "creates the ephemeral UpdateConfig with that target_branch" do
        expect { run }.to change(UpdateConfig, :count).by(1)
        expect(UpdateConfig.last.target_branch).to eq("feature-branch")
      end

      it "reuses an existing ephemeral UpdateConfig with the same target_branch" do
        existing = create(:update_config, :active, update_schedule: "never", repo:, package_manager:,
                                                   target_branch: "feature-branch", directory: nil,
                                                   directories: ["/old"])

        expect { run }.not_to change(UpdateConfig, :count)
        expect(run).to eq({ existing => ["/"] })
      end

      it "does not match an ephemeral UpdateConfig from a different branch" do
        create(:update_config, :active, update_schedule: "never", repo:, package_manager:,
                                        target_branch: "main", directory: nil, directories: ["/"])

        expect { run }.to change(UpdateConfig, :count).by(1)
        expect(UpdateConfig.last.target_branch).to eq("feature-branch")
      end
    end
  end
end
