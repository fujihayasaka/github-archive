# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindOrCreateUpdateConfig do
  subject(:action) do
    described_class.new(
      repo: repo,
      update_config_details: params_hash,
      user: user,
    )
  end

  let(:repo) { FactoryBot.create(:repo) }
  let(:github_client) { Octokit::Client.new(access_token: "junk") }
  let(:user) do
    stub_request(:get, "https://api.github.com/user").to_return(
      status: 200,
      body: fixture("github_responses/user.json"),
      headers: { "Content-Type" => "application/json" },
    )
    github_client.user
  end
  let(:directory) { "/" }
  let(:directories) { nil }
  let(:params_hash) do
    {
      "update-schedule" => schedule,
      "directory" => directory,
      "directories" => directories,
      "package-manager" => package_manager,
      "vendor" => true,
    }
  end

  let(:cooldown_settings) do
    {
      "default-days" => 5,
      "semver-major-days" => 10,
      "semver-minor-days" => 3,
      "semver-patch-days" => 1,
      "include" => ["dependency-2"],
      "exclude" => ["dependency-3"],
    }
  end
  let(:schedule) { "daily" }
  let(:package_manager) { "bundler" }

  context "for an update config that already exists" do
    let!(:existing_update_config) do
      FactoryBot.create(
        :update_config, :active,
        repo: repo,
        directory: "/.",
        package_manager: package_manager,
      )
    end

    it "does not create a new update config" do
      expect { action.run }.not_to change(UpdateConfig, :count)
    end

    it "returns the existing update config" do
      expect(action.run).to eq(existing_update_config)
    end

    context "when a duplicate config exists due to a race condition" do
      let(:mock_relation) do
        double(UpdateConfig.active)
      end

      before do
        allow(mock_relation).to receive(:find_by).
          and_return(:nil, existing_update_config)

        allow(UpdateConfig).to receive(:active).
          and_return(mock_relation)
      end

      it "does not create a new update config" do
        expect { action.run }.not_to change(UpdateConfig, :count)
      end

      it "returns the existing config" do
        expect(action.run).to eq(existing_update_config)
      end
    end
  end

  context "for an update config that already exists with directories" do
    let(:directories) { ["/foo", "/bar"] }
    let!(:existing_update_config) do
      FactoryBot.create(
        :update_config, :active,
        repo: repo,
        directory: nil,
        directories: ["/bar", "/foo"],
        package_manager: package_manager,
      )
    end

    it "does not create a new update config" do
      expect { action.run }.not_to change(UpdateConfig, :count)
    end

    it "returns the existing update config" do
      expect(action.run).to eq(existing_update_config)
    end

    context "and an advisory for a new directory is issued" do
      let(:directories) { ["/bar", "/foo", "/test"] }

      it "updates the update config's directories to include the updated advisory path" do
        expect(action.run.directories).to eq(directories)
      end
    end

    context "when a duplicate config exists due to a race condition" do
      let(:mock_relation) do
        double(UpdateConfig.active)
      end

      before do
        # find_by returns nil because of the race condition
        allow(mock_relation).to receive(:find_by).
          and_return(nil)

        # the db has caught up and the exisitng UpdateConfig is found when
        # trying to create the duplicate
        allow(mock_relation).to receive(:exists?).
          and_return(true)
      end

      it "does not create a new update config but returns the existing one" do
        expect(action.run).to eq(existing_update_config)
      end
    end
  end

  context "for an update config that doesn't already exist" do
    it "creates a new update config" do
      expect { action.run }.to change(UpdateConfig, :count).by(1)
      expect(UpdateConfig.last.current_state).to eq("rate_limited")
      expect(UpdateConfig.last.vendor).to eq(true)
    end

    it "sets default options correctly" do
      update_config = action.run

      expect(update_config.update_schedule_time_of_day.strftime("%H:%M")).
        to eq(repo.default_update_schedule_time_of_day)

      expect(update_config.update_schedule_day_of_week).to eq("monday")
      expect(update_config.update_schedule_timezone).to eq("UTC")
      expect(update_config.pull_request_branch_name_separator).to eq("/")
      expect(update_config.open_pull_requests_limit).to eq(5)
      expect(update_config.rebase_strategy).to eq("auto")
      expect(update_config.all_registries).to eq(false)
      expect(update_config.update_schedule_cron_expression).to eq("@daily")
    end

    context "when passing a custom schedule" do
      subject(:update_config) { action.run }

      let(:params_hash) do
        {
          "update-schedule" => schedule,
          "directory" => "",
          "package-manager" => package_manager,
          "update-schedule-time-of-day" => "07:00",
          "update-schedule-day-of-week" => "friday",
          "update-schedule-timezone" => "Europe/Amsterdam",
          "pull-request-branch-name-separator" => "-",
          "rebase-strategy" => "disabled",
          "open-pull-requests-limit" => 6,
          "update-schedule-cron-expression" => "0 5 * * *",
        }
      end

      it "sets all values from the schedule parameters correctly" do
        expect(update_config.update_schedule_time_of_day.hour).to eq(7)
        expect(update_config.update_schedule_day_of_week).to eq("friday")
        expect(update_config.update_schedule_timezone).to eq("Europe/Amsterdam")
        expect(update_config.pull_request_branch_name_separator).to eq("-")
        expect(update_config.open_pull_requests_limit).to eq(6)
        expect(update_config.rebase_strategy).to eq("disabled")
        expect(update_config.update_schedule_cron_expression).to eq("0 5 * * *")
      end
    end

    context "with enable_beta_ecosystems set" do
      subject(:update_config) { action.run }

      let(:params_hash) do
        {
          "update-schedule" => schedule,
          "directory" => "/",
          "package-manager" => package_manager,
          "enable-beta-ecosystems" => true,
        }
      end

      it "sets enable_beta_ecosystems correctly" do
        expect(update_config.enable_beta_ecosystems).to eq(true)
      end
    end

    context "without enable_beta_ecosystems set" do
      subject(:update_config) { action.run }

      let(:params_hash) do
        {
          "update-schedule" => schedule,
          "directory" => "/",
          "package-manager" => package_manager,
        }
      end

      it "defaults enable_beta_ecosystems to false" do
        expect(update_config.enable_beta_ecosystems).to eq(false)
      end
    end

    it "returns the created update config" do
      expect(action.run).to be_a(UpdateConfig)
    end

    context "without a user" do
      let(:user) { nil }

      it "returns the created update config" do
        expect(action.run).to be_a(UpdateConfig)
      end
    end

    context "with registries wildcard" do
      subject(:update_config) { action.run }

      let(:params_hash) do
        {
          "update-schedule" => schedule,
          "directory" => "/",
          "package-manager" => package_manager,
          "registries" => UpdateConfig::REGISTRY_WILDCARD,
        }
      end

      it "translates this into setting the all_registries flag on the config" do
        expect(update_config.all_registries).to eq(true)
      end
    end

    context "with registries list" do
      subject(:update_config) { action.run }

      let(:params_hash) do
        {
          "update-schedule" => schedule,
          "directory" => "/",
          "package-manager" => package_manager,
          "registries" => %w(registry-1 registry-2),
        }
      end

      it "has only the configured registries" do
        expect(update_config.all_registries).to eq(false)
        expect(update_config.update_config_registries.pluck(:registry_name)).
          to eq(%w(registry-1 registry-2))
      end
    end
  end

  context "when running twice with different directories" do
    let(:directories) { ["/bar", "/foo"] }

    it "finds the existing update config" do
      existing_update_config = FactoryBot.create(
        :update_config, :active,
        repo: repo,
        directory: nil,
        directories: directories,
        package_manager: package_manager,
      )
      expect(UpdateConfig.count).to eq(1)

      expect(action.run).to eq(existing_update_config)
      expect(UpdateConfig.count).to eq(1)
    end
  end

  context "for an update config that doesn't already exist (directories)" do
    let(:directories) { ["/foo", "/bar"] }

    it "creates a new update config" do
      expect { action.run }.to change(UpdateConfig, :count).by(1)
      expect(UpdateConfig.last.current_state).to eq("rate_limited")
      expect(UpdateConfig.last.vendor).to eq(true)
    end

    it "sets default options correctly" do
      update_config = action.run

      expect(update_config.update_schedule_time_of_day.strftime("%H:%M")).
        to eq(repo.default_update_schedule_time_of_day)

      expect(update_config.update_schedule_day_of_week).to eq("monday")
      expect(update_config.update_schedule_timezone).to eq("UTC")
      expect(update_config.pull_request_branch_name_separator).to eq("/")
      expect(update_config.open_pull_requests_limit).to eq(5)
      expect(update_config.rebase_strategy).to eq("auto")
      expect(update_config.all_registries).to eq(false)
      expect(update_config.update_schedule_cron_expression).to eq("@daily")
    end

    context "when passing a custom schedule" do
      subject(:update_config) { action.run }

      let(:params_hash) do
        {
          "update-schedule" => schedule,
          "directory" => "",
          "directories" => directories,
          "package-manager" => package_manager,
          "update-schedule-time-of-day" => "07:00",
          "update-schedule-day-of-week" => "friday",
          "update-schedule-timezone" => "Europe/Amsterdam",
          "pull-request-branch-name-separator" => "-",
          "rebase-strategy" => "disabled",
          "open-pull-requests-limit" => 6,
          "update-schedule-cron-expression" => "0 12 * * *",
        }
      end

      it "sets all values from the schedule parameters correctly" do
        expect(update_config.update_schedule_time_of_day.hour).to eq(7)
        expect(update_config.update_schedule_day_of_week).to eq("friday")
        expect(update_config.update_schedule_timezone).to eq("Europe/Amsterdam")
        expect(update_config.pull_request_branch_name_separator).to eq("-")
        expect(update_config.open_pull_requests_limit).to eq(6)
        expect(update_config.rebase_strategy).to eq("disabled")
        expect(update_config.update_schedule_cron_expression).to eq("0 12 * * *")
      end
    end

    it "returns the created update config" do
      expect(action.run).to be_a(UpdateConfig)
    end

    context "without a user" do
      let(:user) { nil }

      it "returns the created update config" do
        expect(action.run).to be_a(UpdateConfig)
      end
    end

    context "with registries wildcard" do
      subject(:update_config) { action.run }

      let(:params_hash) do
        {
          "update-schedule" => schedule,
          "directory" => "/",
          "directories" => directories,
          "package-manager" => package_manager,
          "registries" => UpdateConfig::REGISTRY_WILDCARD,
        }
      end

      it "translates this into setting the all_registries flag on the config" do
        expect(update_config.all_registries).to eq(true)
      end
    end

    context "with registries list" do
      subject(:update_config) { action.run }

      let(:params_hash) do
        {
          "update-schedule" => schedule,
          "directory" => "/",
          "directories" => directories,
          "package-manager" => package_manager,
          "registries" => %w(registry-1 registry-2),
        }
      end

      it "has only the configured registries" do
        expect(update_config.all_registries).to eq(false)
        expect(update_config.update_config_registries.pluck(:registry_name)).
          to eq(%w(registry-1 registry-2))
      end
    end
  end

  context "for an update config that doesn't already exist with both directory and directories set" do
    let(:directory) { "/" }
    let(:directories) { ["/bar", "/foo"] }

    it "creates a new update config with only directories defined" do
      expect { action.run }.to change(UpdateConfig, :count).by(1)
      expect(UpdateConfig.last.directories).to eq(directories)
      expect(UpdateConfig.last.directory).to eq(nil)
    end
  end

  context "for an update config that doesn't already exist with an emoji directory name" do
    let(:directory) { "/😅" }

    it "creates a new update config" do
      expect { action.run }.to change(UpdateConfig, :count).by(1)
      expect(UpdateConfig.last.current_state).to eq("rate_limited")
      expect(UpdateConfig.last.directory).to eq(directory)
    end
  end

  context "for an update config that doesn't already exist with an emoji directories names" do
    let(:directory) { "/😅" }
    let(:directories) { ["/bar/😅", "/foo/😅"] }

    it "creates a new update config" do
      expect { action.run }.to change(UpdateConfig, :count).by(1)
      expect(UpdateConfig.last.current_state).to eq("rate_limited")
      expect(UpdateConfig.last.directory).to eq(nil)
      expect(UpdateConfig.last.directories).to eq(directories)
    end
  end

  context "for an update config that already exists with an emoji directory name" do
    let(:directory) { "/😅" }

    let!(:existing_update_config) do
      FactoryBot.create(
        :update_config, :active,
        repo: repo,
        directory: directory,
        package_manager: package_manager,
      )
    end

    it "does not create a new update config" do
      expect { action.run }.not_to change(UpdateConfig, :count)
    end

    it "returns the existing update config" do
      expect(action.run).to eq(existing_update_config)
    end
  end

  context "for an update config that already exists with an emoji directories name" do
    let(:directory) { nil }
    let(:directories) { ["/bar/😅", "/foo/😅"] }

    let!(:existing_update_config) do
      FactoryBot.create(
        :update_config, :active,
        repo: repo,
        directory: directory,
        directories: directories,
        package_manager: package_manager,
      )
    end

    it "does not create a new update config" do
      expect { action.run }.not_to change(UpdateConfig, :count)
      expect(UpdateConfig.last.directory).to eq(nil)
      expect(UpdateConfig.last.directories).to eq(directories)
    end

    it "returns the existing update config" do
      expect(action.run).to eq(existing_update_config)
    end
  end

  context "for an update config that doesn't already exist with a really long directory name" do
    let(:really_long_directory_name) do
      "/😅/" + "a" * 1000
    end
    let(:directory) { really_long_directory_name }

    it "creates a new update config" do
      expect { action.run }.to change(UpdateConfig, :count).by(1)
      expect(UpdateConfig.last.current_state).to eq("rate_limited")
      expect(UpdateConfig.last.directory).to eq(directory)
    end
  end

  context "for an update config that doesn't already exist with a really long directory name in directories list" do
    let(:really_long_directory_name) do
      "/😅/" + "a" * 1000
    end
    let(:directory) { "/😅" }
    let(:directories) { ["/bar/😅", really_long_directory_name] }

    it "creates a new update config" do
      expect { action.run }.to change(UpdateConfig, :count).by(1)
      expect(UpdateConfig.last.current_state).to eq("rate_limited")
      expect(UpdateConfig.last.directory).to eq(nil)
      expect(UpdateConfig.last.directories).to eq(directories)
    end
  end

  context "for an update config that already exists with a really long directory name" do
    let(:really_long_directory_name) do
      "/😅/" + "a" * 1000
    end
    let(:directory) { really_long_directory_name }

    let!(:existing_update_config) do
      FactoryBot.create(
        :update_config, :active,
        repo: repo,
        directory: directory,
        package_manager: package_manager,
      )
    end

    it "does not create a new update config" do
      expect { action.run }.not_to change(UpdateConfig, :count)
    end

    it "returns the existing update config" do
      expect(action.run).to eq(existing_update_config)
    end
  end

  context "for an update config that already exists with a really long directory name in the directories list" do
    let(:really_long_directory_name) do
      "/😅/" + "a" * 1000
    end
    let(:directory) { really_long_directory_name }
    let(:directories) { ["/bar/😅", really_long_directory_name] }

    let!(:existing_update_config) do
      FactoryBot.create(
        :update_config, :active,
        repo: repo,
        directory: nil,
        directories: directories,
        package_manager: package_manager,
      )
    end

    it "does not create a new update config" do
      expect { action.run }.not_to change(UpdateConfig, :count)
    end

    it "returns the existing update config" do
      expect(action.run).to eq(existing_update_config)
    end
  end

  context "when an update config already exists with cooldown settings" do
    let!(:existing_update_config) do
      FactoryBot.create(
        :update_config, :active,
        repo: repo,
        directory: "/.",
        directories: directories,
        package_manager: package_manager,
      )
    end
    let(:params_hash) do
      {
        "update-schedule" => schedule,
        "directory" => directory,
        "directories" => directories,
        "package-manager" => package_manager,
        "vendor" => true,
      }
    end

    let!(:existing_cooldown) do
      FactoryBot.create(
        :update_config_cooldown,
        update_config: existing_update_config,
        default_days: 7,
        semver_major_days: 14,
        semver_minor_days: 5,
        semver_patch_days: 2,
        include: ["dependency-1"],
        exclude: ["dependency-2"],
      )
    end

    it "does not create a new update config" do
      expect { action.run }.not_to change(UpdateConfig, :count)
    end

    it "does not create a new cooldown" do
      expect { action.run }.not_to change(UpdateConfigCooldown, :count)
    end

    it "returns the existing update config" do
      result = action.run
      expect(result).to eq(existing_update_config)
    end

    it "does not modify the cooldown settings" do
      expect { action.run }.not_to change { existing_cooldown.reload.attributes }
    end
  end

  context "when an update config exists but has no cooldown" do
    let!(:existing_update_config) do
      FactoryBot.create(
        :update_config, :active,
        repo: repo,
        directory: directory,
        directories: directories,
        package_manager: package_manager,
      )
    end

    let(:params_hash) do
      {
        "update-schedule" => schedule,
        "directory" => directory,
        "directories" => directories,
        "package-manager" => package_manager,
        "vendor" => true,
        "cooldown" => cooldown_settings,
      }
    end

    it "creates a new cooldown record" do
      expect { action.run }.to change(UpdateConfigCooldown, :count).by(1)
    end

    it "sets the cooldown settings correctly" do
      action.run
      existing_update_config.reload # ✅ Reload to ensure association is fresh

      cooldown = UpdateConfig.last.update_config_cooldown

      expect(cooldown).not_to be_nil
      expect(cooldown.default_days).to eq(5)
      expect(cooldown.semver_major_days).to eq(10)
      expect(cooldown.semver_minor_days).to eq(3)
      expect(cooldown.semver_patch_days).to eq(1)
      expect(cooldown.include).to eq(["dependency-2"])
      expect(cooldown.exclude).to eq(["dependency-3"])
    end
  end

  context "when an update config exists with the same multi_ecosystem_config_id" do
    let(:multi_ecosystem_config) { create(:multi_ecosystem_config) }
    let(:params_hash) do
      {
        "update-schedule" => schedule,
        "directory" => "/",
        "directories" => directories,
        "package-manager" => package_manager,
        "vendor" => true,
        "multi_ecosystem_config_id" => multi_ecosystem_config.id,
      }
    end

    before do
      update_config = create(
        :update_config, :active,
        repo: repo,
        directory: "/.",
        directories: directories,
        package_manager: package_manager,
      )
      update_config.update!(multi_ecosystem_config:)
    end

    it "does not create a new update config" do
      expect { action.run }.not_to change(UpdateConfig, :count)
    end
  end
end
