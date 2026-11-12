# frozen_string_literal: true

require "rails_helper"

require_relative "../../../../lib/dependabot/transitions/20240314002209_sort_groups_by_resync.rb"
RSpec.describe Dependabot::Transitions::SortGroupsByResync do
  include ActiveJob::TestHelper

  let(:transition) do
    described_class.new(dry_run: false)
  end
  let(:config_file_path) { ".github/dependabot.yml" }
  let(:config_file_body) do
    <<~YAML
      version: 2
      updates:
        - package-ecosystem: "bundler"
          directory: "/"
          schedule:
            interval: "daily"
          groups:
            some-other-group:
              patterns:
                - "some-other-group"
            warp:
              patterns:
                - "warp"
    YAML
  end
  let(:repo) do
    create(:repo,
           account: account,
           name: "dependabot-test",
           github_id: 88632334,
           config_file_path: config_file_path,)
  end
  let!(:update_config) { create(:update_config, :active, repo: repo, directory: "/.") }

  let(:dry_run_transition) do
    described_class.new
  end

  let(:account) { FactoryBot.create(:account, :dependabot, :active) }

  let(:config_file) do
    OpenStruct.new(
      path: ".github/dependabot.yml",
      content: config_file_body,
    )
  end

  let(:dummy_config_file_fetcher) do
    instance_double(FetchConfigFile, run: config_file)
  end

  before do
    allow(FetchConfigFile).
      to receive(:new).with(hash_including(repo_name: repo.name)).
      and_return(dummy_config_file_fetcher)
  end

  context "write" do
    before do
      repo.enable_feature(:sort_order) # rubocop:disable Dependabot/NoLocalFeatureFlags
    end

    after do
      clear_enqueued_jobs
    end

    context "performs the transition" do
      context "for a repo with a dependency group" do
        before do
          create(:dependency_group, :active, update_config: update_config, name: "warp")
        end

        it "enqueues a resync job for the repo" do
          expect(Repo.joins(:update_configs).merge(UpdateConfig.active).
                 where.not(update_configs: { dependency_groups: nil }).distinct.count).to eq(1)

          # The sort order is not set for existing repositories
          expect(repo.update_configs.first.dependency_groups.first.sort_order).to eq(nil)

          transition.perform
          perform_enqueued_jobs

          # The job calls ProcessConfigFile which sets the sort order on the dependency groups
          # warp is the second dependency group in the config file
          expect(repo.update_configs.first.dependency_groups.where(name: "warp").first.sort_order).to eq(1)
        end
      end

      context "for a repo with multiple dependency groups" do
        before do
          create(:dependency_group, :active, update_config: update_config, name: "warp")

          update_config2 = create(:update_config, :active, repo: repo, directories: ["/app", "/lib"], directory: nil)
          create(:dependency_group, :active, update_config: update_config2, name: "combo")
        end

        let(:config_file_body) do
          <<~YAML
            version: 2
            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                schedule:
                  interval: "daily"
                groups:
                  some-other-group:
                    patterns:
                      - "some-other-group"
                  warp:
                    patterns:
                      - "warp"
              - package-ecosystem: "bundler"
                directories: ["/app", "/lib"]
                schedule:
                  interval: "daily"
                groups:
                  combo:
                    patterns:
                      - "combo"
          YAML
        end

        it "only enqueues the repo once" do
          expect(UpdateConfig.active.where.not(dependency_groups: nil).count).to eq(2)
          expect(Repo.joins(:update_configs).merge(UpdateConfig.active).
                 where.not(update_configs: { dependency_groups: nil }).distinct.count).to eq(1)

          expect(repo.update_configs.first.dependency_groups.first.sort_order).to eq(nil)

          transition.perform
          expect(ResyncRepoConfigFileJob).to have_been_enqueued.exactly(1).times

          perform_enqueued_jobs

          # warp was the second group in the config file
          expect(repo.update_configs.where(directories: nil).first.
                 dependency_groups.where(name: "warp").first.sort_order).to eq(1)
          expect(repo.update_configs.where(directory: nil).first.dependency_groups.first.sort_order).to eq(0)
        end
      end

      context "for multiple repos with a dependency group" do
        let(:config_file2) do
          OpenStruct.new(
            path: ".github/dependabot.yml",
            content: config_file_body2,
          )
        end

        let(:config_file_body2) do
          <<~YAML
            version: 2
            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                schedule:
                  interval: "daily"
                groups:
                  test:
                    patterns:
                      - "test"
          YAML
        end

        let(:repo2) do
          create(:repo,
                 account: account,
                 name: "dependabot-test2",
                 github_id: 88632335,
                 config_file_path: config_file_path,)
        end

        let(:dummy_config_file_fetcher2) do
          instance_double(FetchConfigFile, run: config_file2)
        end

        before do
          allow(FetchConfigFile).
            to receive(:new).with(hash_including(repo_name: repo2.name)).
            and_return(dummy_config_file_fetcher2)

          create(:dependency_group, :active, update_config: update_config, name: "warp")

          update_config2 = create(:update_config, :active, repo: repo2, directory: "/.")
          create(:dependency_group, :active, update_config: update_config2, name: "test")
        end

        it "runs a resync job on each repo and sets the sort order" do
          expect(Repo.joins(:update_configs).merge(UpdateConfig.active).
                 where.not(update_configs: { dependency_groups: nil }).distinct.count).to eq(2)

          expect(repo.update_configs.first.dependency_groups.first.sort_order).to eq(nil)
          expect(repo2.update_configs.first.dependency_groups.first.sort_order).to eq(nil)

          transition.perform
          expect(ResyncRepoConfigFileJob).to have_been_enqueued.exactly(2).times

          perform_enqueued_jobs

          expect(repo.update_configs.first.dependency_groups.sort_by(&:sort_order).map(&:name)).
            to eq(%w(some-other-group warp))
          expect(repo2.update_configs.first.dependency_groups.sort_by(&:sort_order).map(&:name)).
            to eq(["test"])
        end
      end

      context "for a repo without a dependency group" do
        let(:config_file_body) do
          <<~YAML
            version: 2
            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                schedule:
                  interval: "daily"
          YAML
        end

        it "does not run a resync job" do
          expect(Repo.joins(:update_configs).merge(UpdateConfig.active).count).to eq(1)

          transition.perform

          expect(ResyncRepoConfigFileJob).not_to have_been_enqueued
        end
      end
    end
  end

  context "dry run" do
    before do
      create(:dependency_group, :active, update_config: update_config, name: "warp")
    end

    it "does not resync any repos" do
      expect(Repo.joins(:update_configs).merge(UpdateConfig.active).
             where.not(update_configs: { dependency_groups: nil }).distinct.count).to eq(1)

      dry_run_transition.perform

      expect(ResyncRepoConfigFileJob).not_to have_been_enqueued
    end
  end
end
