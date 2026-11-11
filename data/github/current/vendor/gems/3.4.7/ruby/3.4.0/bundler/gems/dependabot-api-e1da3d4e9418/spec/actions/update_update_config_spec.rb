# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateUpdateConfig do
  include ActiveSupport::Testing::TimeHelpers

  subject(:action) do
    described_class.new(
      update_config: update_config,
      update_config_details: params_hash,
    )
  end

  let(:update_config) { FactoryBot.create(:update_config, :active) }
  let(:params_hash) do
    hash = { "update-schedule" => schedule, "directory" => directory, "directories" => directories }
    hash
  end
  let(:schedule) { "daily" }
  let(:directory) { "/new_directory" }
  let(:directories) { nil }

  context "with a valid update schedule" do
    let(:schedule) { "weekly" }

    it "updates the schedule" do
      expect { action.run }.
        to change(update_config, :update_schedule).to("weekly")
    end
  end

  context "without a schedule" do
    before { update_config.update!(update_schedule: "weekly") }

    let(:params_hash) do
      hash = { "directory" => directory }
      hash
    end

    it "doesn't update the schedule" do
      expect { action.run }.not_to change(update_config, :update_schedule)
    end
  end

  context "without a directory" do
    before { update_config.update!(directory: "/some/directory") }

    let(:params_hash) do
      hash = { "update-schedule" => schedule }
      hash
    end

    it "doesn't update the directory" do
      expect { action.run }.not_to change(update_config, :directory)
    end
  end

  context "without directories" do
    before { update_config.update!(directory: nil, directories: ["/bar/directory", "/foo/directory"]) }

    let(:params_hash) do
      hash = { "update-schedule" => schedule }
      hash
    end

    it "does not change any existing directories" do
      expect { action.run }.not_to change(update_config, :directories)
    end
  end

  context "with a valid directory" do
    let(:directory) { "some/directory/" }

    it "updates the directory (and fixes up slashes)" do
      expect { action.run }.
        to change(update_config, :directory).to("/some/directory")
    end

    context "that is the existing directory" do
      before { update_config.update!(directory: "/some/directory") }

      it "does nothing" do
        expect { action.run }.
          not_to change(update_config, :directory)
      end
    end

    context "that already exists for some other update config" do
      let!(:other_update_config) do
        FactoryBot.create(
          :update_config, :active,
          repo: update_config.repo,
          directory: "/some/directory",
        )
      end

      it "doesn't update the directory" do
        expect { action.run }.to raise_error(ActiveRecord::RecordInvalid)
      end

      context "that is inactive" do
        before { other_update_config.transition_to!(:deleted) }

        it "updates the directory (and fixes up slashes)" do
          expect { action.run }.
            to change(update_config, :directory).to("/some/directory")
        end
      end
    end
  end

  context "with valid directories" do
    let(:update_config) { FactoryBot.create(:update_config, :active, directory: nil, directories: ["/."]) }
    let(:directory) { nil }
    let(:directories) { ["bar/directory/", "/foo/directory/"] }

    it "updates the directory (and fixes up slashes)" do
      expect { action.run }.
        to change(update_config, :directories).to(["/bar/directory", "/foo/directory"])
    end

    context "that is the existing directory" do
      before { update_config.update!(directories: ["/bar/directory", "/foo/directory"]) }

      it "does nothing" do
        expect { action.run }.
          not_to change(update_config, :directories)
      end
    end

    context "that already exists for some other update config" do
      let!(:other_update_config) do
        FactoryBot.create(
          :update_config, :active,
          repo: update_config.repo,
          directory: nil,
          directories: ["/bar/directory", "/foo/directory"],
        )
      end

      it "doesn't update the directories" do
        skip "It should raise but we need another PR to fix this"
        expect { action.run }.to raise_error(ActiveRecord::RecordInvalid)
      end

      context "that is inactive" do
        before { other_update_config.transition_to!(:deleted) }

        it "updates the directories (and fixes up slashes)" do
          expect { action.run }.
            to change(update_config, :directories).to(["/bar/directory", "/foo/directory"])
        end
      end
    end
  end

  context "updating the target branch" do
    let(:params_hash) do
      hash = { "target-branch" => target_branch }
      hash
    end
    let(:target_branch) { "lgtm" }

    it "updates the target branch" do
      expect { action.run }.
        to change(update_config, :target_branch).to("lgtm")
    end

    context "when setting the target branch to the default" do
      before { update_config.update!(target_branch: "custom_branch") }

      let(:target_branch) { nil }

      it "updates the target branch" do
        expect { action.run }.
          to change(update_config, :target_branch).to(nil)
      end

      context "when no target-branch key was passed" do
        let(:params_hash) do
          hash = {}
          hash
        end

        it "does not update the target branch" do
          expect { action.run }.not_to change(update_config, :target_branch)
        end
      end
    end
  end

  context "updating default labels" do
    let(:params_hash) do
      hash = { "custom-labels" => labels }
      hash
    end
    let(:labels) { ["bug"] }

    it "updates the setting" do
      expect { action.run }.
        to change(update_config, :custom_labels).
        from(nil).to(["bug"])
    end

    context "with duplicate labels" do
      let(:labels) { %w(bug bug) }

      it "updates the setting" do
        expect { action.run }.
          to change(update_config, :custom_labels).
          from(nil).to(["bug"])
      end
    end

    context "with existing labels" do
      let(:labels) { nil }

      before { update_config.update!(custom_labels: ["bug"]) }

      it "updates the setting" do
        expect { action.run }.
          to change(update_config, :custom_labels).
          from(["bug"]).to(nil)
      end
    end

    context "with labels in mismatching case" do
      let(:labels) { ["Bug"] }

      it "updates the setting" do
        expect { action.run }.
          to change(update_config, :custom_labels).
          from(nil).to(["Bug"])
      end
    end

    context "with empty labels" do
      let(:labels) { [] }

      it "updates the setting" do
        expect { action.run }.
          to change(update_config, :custom_labels).
          from(nil).to([])
      end
    end
  end

  context "updating default milestone" do
    let(:params_hash) do
      hash = { "default-milestone" => milestone }
      hash
    end
    let(:milestone) { 3 }

    it "updates the setting" do
      expect { action.run }.
        to change(update_config, :default_milestone).
        from(nil).to(3)
    end

    context "with an existing milestone" do
      let(:milestone) { nil }

      before { update_config.update!(default_milestone: 1) }

      it "updates the setting" do
        expect { action.run }.
          to change(update_config, :default_milestone).
          from(1).to(nil)
      end
    end
  end

  context "updating default assignees" do
    let(:params_hash) do
      hash = { "default-assignees" => assignees }
      hash
    end
    let(:assignees) { ["bender"] }

    it "updates the setting" do
      expect { action.run }.
        to change(update_config, :default_assignees).
        from(nil).to(["bender"])
    end

    context "when assignee doesn't exist in github" do
      let(:assignees) { ["frank"] }

      # TODO: Fix me?
      #
      # This test captures existing behaviour, but it doesn't seem
      # like this is working as intended.
      it "updates the setting" do
        expect { action.run }.
          to change(update_config, :default_assignees).
          from(nil).to(["frank"])
      end
    end

    context "with duplicate assignees" do
      let(:assignees) { %w(bender bender) }

      it "updates the setting" do
        expect { action.run }.
          to change(update_config, :default_assignees).
          from(nil).to(["bender"])
      end
    end

    context "with existing assignees" do
      let(:assignees) { nil }

      before { update_config.update!(default_assignees: ["bender"]) }

      it "updates the setting" do
        expect { action.run }.
          to change(update_config, :default_assignees).
          from(["bender"]).to(nil)
      end
    end

    context "with assignees in mismatching case" do
      let(:assignees) { ["Bender"] }

      it "updates the setting" do
        expect { action.run }.
          to change(update_config, :default_assignees).
          from(nil).to(["Bender"])
      end
    end
  end

  context "updating commit message options" do
    context "updating the prefix" do
      let(:params_hash) do
        hash = { "commit-message-prefix" => prefix }
        hash
      end
      let(:prefix) { "chore" }

      it "updates the setting" do
        expect { action.run }.
          to change(update_config, :commit_message_prefix).
          from(nil).to("chore")
      end

      context "when a commit message prefix is already set" do
        before { update_config.update!(commit_message_prefix: "test") }

        context "and `nil` is provided" do
          let(:prefix) { nil }

          it "updates the setting" do
            expect { action.run }.
              to change(update_config, :commit_message_prefix).
              from("test").to(nil)
          end
        end

        context "and the key is omitted" do
          let(:params_hash) do
            hash = { "default-reviewers" => { "reviewers" => ["greysteil"] } }
            hash
          end

          it "does not update the setting" do
            expect { action.run }.
              not_to change(update_config, :commit_message_prefix).
              from("test")
          end
        end
      end
    end

    context "updating the development prefix" do
      let(:params_hash) do
        hash = { "commit-message-prefix-development" => prefix }
        hash
      end
      let(:prefix) { "chore" }

      it "updates the setting" do
        expect { action.run }.
          to change(update_config, :commit_message_prefix_development).
          from(nil).to("chore")
      end

      context "when a prefix is already set" do
        before do
          update_config.update!(commit_message_prefix_development: "test")
        end

        context "and `nil` is provided" do
          let(:prefix) { nil }

          it "updates the setting" do
            expect { action.run }.
              to change(update_config, :commit_message_prefix_development).
              from("test").to(nil)
          end
        end

        context "and the key is omitted" do
          let(:params_hash) do
            hash = { "default-reviewers" => {} }
            hash
          end

          it "does not update the setting" do
            expect { action.run }.
              not_to change(update_config, :commit_message_prefix_development).
              from("test")
          end
        end
      end
    end

    context "updating whether the dependency scope is included" do
      let(:params_hash) do
        hash = { "commit-message-include-scope" => include_scope }
        hash
      end
      let(:include_scope) { false }

      it "updates the setting" do
        expect { action.run }.
          to change(update_config, :commit_message_include_scope).
          from(nil).to(false)
      end

      context "when already set" do
        before { update_config.update!(commit_message_include_scope: false) }

        context "and `nil` is provided" do
          let(:include_scope) { nil }

          it "updates the setting" do
            expect { action.run }.
              to change(update_config, :commit_message_include_scope).
              from(false).to(nil)
          end
        end

        context "and the key is omitted" do
          let(:params_hash) do
            hash = { "default-reviewers" => {} }
            hash
          end

          it "does not update the setting" do
            expect { action.run }.
              not_to change(update_config, :commit_message_include_scope).
              from(false)
          end
        end
      end
    end
  end

  context "updating update_schedule_time_of_day" do
    let(:params_hash) do
      hash = { "update-schedule-time-of-day" => time_of_day }
      hash
    end
    let(:time_of_day) { "04:20" }
    let(:default_schedule_time) { "05:00" }

    it "updates the setting" do
      action.run

      expect(update_config.reload.update_schedule_time_of_day.strftime("%H:%M")).
        to eq(time_of_day)
    end

    context "when midnight" do
      let(:time_of_day) { "00:00" }

      it "updates the setting" do
        action.run

        expect(update_config.reload.update_schedule_time_of_day.strftime("%H:%M")).
          to eq(time_of_day)
      end
    end

    context "when a update_schedule_time_of_day is already set" do
      before { update_config.update!(update_schedule_time_of_day: "20:00") }

      context "and `nil` is provided" do
        let(:time_of_day) { nil }

        it "updates the setting to the repository's default" do
          action.run

          expect(update_config.reload.update_schedule_time_of_day.strftime("%H:%M")).
            to eq(update_config.repo.default_update_schedule_time_of_day)
        end
      end

      context "and the key is omitted" do
        let(:params_hash) do
          hash = { "default-reviewers" => {} }
          hash
        end

        it "updates the setting to the repository's default" do
          action.run

          expect(update_config.reload.update_schedule_time_of_day.strftime("%H:%M")).
            to eq(update_config.repo.default_update_schedule_time_of_day)
        end
      end
    end
  end

  context "updating update_schedule_day_of_week" do
    let(:params_hash) do
      hash = { "update-schedule-day-of-week" => day_of_week }
      hash
    end
    let(:day_of_week) { "tuesday" }

    it "updates the setting" do
      expect { action.run }.
        to change(update_config, :update_schedule_day_of_week).
        from(UpdateConfig::DEFAULT_UPDATE_SCHEDULE_DAY_OF_WEEK).to("tuesday")
    end

    context "when a update_schedule_day_of_week is already set" do
      before { update_config.update!(update_schedule_day_of_week: "wednesday") }

      context "and `nil` is provided" do
        let(:day_of_week) { nil }

        it "updates the setting to the default" do
          expect { action.run }.
            to change(update_config, :update_schedule_day_of_week).
            from("wednesday").to(
              UpdateConfig::DEFAULT_UPDATE_SCHEDULE_DAY_OF_WEEK
            )
        end
      end

      context "and the key is omitted" do
        let(:params_hash) do
          hash = { "default-reviewers" => {} }
          hash
        end

        it "does not update the setting" do
          expect { action.run }.
            not_to change(update_config, :update_schedule_day_of_week).
            from("wednesday")
        end
      end
    end
  end

  context "updating update_schedule_cron_expression" do
    let(:params_hash) do
      hash = { "update-schedule-cron-expression" => cron_expression }
      hash
    end
    let(:cron_expression) { "0 5 * * *" }

    it "updates the setting" do
      expect { action.run }.
        to change(update_config, :update_schedule_cron_expression).
        from(UpdateConfig::DEFAULT_UPDATE_SCHEDULE_CRON_EXPRESSION).to("0 5 * * *")
    end

    context "when a update_schedule_cron_expression is already set" do
      before { update_config.update!(update_schedule_cron_expression: "0 6 * * *") }

      context "and `nil` is provided" do
        let(:cron_expression) { nil }

        it "updates the setting to the default" do
          expect { action.run }.
            to change(update_config, :update_schedule_cron_expression).
            from("0 6 * * *").to(
              UpdateConfig::DEFAULT_UPDATE_SCHEDULE_CRON_EXPRESSION
            )
        end
      end

      context "and the key is omitted" do
        let(:params_hash) do
          hash = { "default-reviewers" => {} }
          hash
        end

        it "does not update the setting" do
          expect { action.run }.
            not_to change(update_config, :update_schedule_cron_expression).
            from("0 6 * * *")
        end
      end
    end
  end

  context "updating update_schedule_timezone" do
    let(:params_hash) do
      hash = { "update-schedule-timezone" => timezone }
      hash
    end
    let(:timezone) { "Europe/Paris" }

    it "updates the setting" do
      expect { action.run }.
        to change(update_config, :update_schedule_timezone).
        from(UpdateConfig::DEFAULT_UPDATE_SCHEDULE_TIMEZONE).to("Europe/Paris")
    end

    context "when a update_schedule_timezone is already set" do
      before do
        update_config.update!(update_schedule_timezone: "Europe/London")
      end

      context "and `nil` is provided" do
        let(:timezone) { nil }

        it "updates the setting to the default" do
          expect { action.run }.
            to change(update_config, :update_schedule_timezone).
            from("Europe/London").to(
              UpdateConfig::DEFAULT_UPDATE_SCHEDULE_TIMEZONE
            )
        end
      end

      context "and the key is omitted" do
        let(:params_hash) do
          hash = { "default-reviewers" => {} }
          hash
        end

        it "does not update the setting" do
          expect { action.run }.
            not_to change(update_config, :update_schedule_timezone).
            from("Europe/London")
        end
      end
    end
  end

  context "updating pull_request_branch_name_separator" do
    let(:params_hash) do
      hash = { "pull-request-branch-name-separator" => separator }
      hash
    end
    let(:separator) { "-" }

    it "updates the setting" do
      expect { action.run }.
        to change(update_config, :pull_request_branch_name_separator).
        from(UpdateConfig::DEFAULT_PULL_REQUEST_BRANCH_NAME_SEPARATOR).to("-")
    end

    context "when a pull_request_branch_name_separator is already set" do
      before { update_config.update!(pull_request_branch_name_separator: "-") }

      context "and `nil` is provided" do
        let(:separator) { nil }

        it "updates the setting to the default" do
          expect { action.run }.
            to change(update_config, :pull_request_branch_name_separator).
            from("-").to(
              UpdateConfig::DEFAULT_PULL_REQUEST_BRANCH_NAME_SEPARATOR
            )
        end
      end

      context "and the key is omitted" do
        let(:params_hash) do
          hash = { "default-reviewers" => {} }
          hash
        end

        it "does not update the setting" do
          expect { action.run }.
            not_to change(update_config, :pull_request_branch_name_separator).
            from("-")
        end
      end
    end
  end

  context "updating open_pull_requests_limit" do
    let(:params_hash) do
      hash = { "open-pull-requests-limit" => limit }
      hash
    end
    let(:limit) { 99 }

    it "updates the setting" do
      expect { action.run }.
        to change(update_config, :open_pull_requests_limit).
        from(UpdateConfig::DEFAULT_OPEN_PULL_REQUESTS_LIMIT).to(99)
    end

    context "when a open_pull_requests_limit is already set" do
      before { update_config.update!(open_pull_requests_limit: 25) }

      context "and `nil` is provided" do
        let(:limit) { nil }

        it "updates the setting to the default" do
          expect { action.run }.
            to change(update_config, :open_pull_requests_limit).
            from(25).to(UpdateConfig::DEFAULT_OPEN_PULL_REQUESTS_LIMIT)
        end
      end

      context "and the key is omitted" do
        let(:params_hash) do
          hash = { "default-reviewers" => {} }
          hash
        end

        it "does not update the setting" do
          expect { action.run }.
            not_to change(update_config, :open_pull_requests_limit).
            from(25)
        end
      end
    end
  end

  context "updating rebase_strategy" do
    let(:params_hash) do
      hash = { "rebase-strategy" => strategy }
      hash
    end
    let(:strategy) { "disabled" }

    it "updates the setting" do
      expect { action.run }.
        to change(update_config, :rebase_strategy).
        from(UpdateConfig::DEFAULT_REBASE_STRATEGY).to("disabled")
    end

    context "when a rebase_strategy is already set" do
      before { update_config.update!(rebase_strategy: "disabled") }

      context "and `nil` is provided" do
        let(:strategy) { nil }

        it "updates the setting to the default" do
          expect { action.run }.
            to change(update_config, :rebase_strategy).
            from("disabled").to(UpdateConfig::DEFAULT_REBASE_STRATEGY)
        end
      end

      context "and the key is omitted" do
        let(:params_hash) do
          hash = { "default-reviewers" => {} }
          hash
        end

        it "does not update the setting" do
          expect { action.run }.
            not_to change(update_config, :rebase_strategy).
            from("disabled")
        end
      end
    end
  end

  context "updating vendor" do
    let(:params_hash) do
      hash = { "vendor" => vendor }
      hash
    end
    let(:vendor) { true }

    it "updates the setting" do
      expect { action.run }.
        to change(update_config, :vendor).
        from(false).to(true)
    end
  end

  context "updating insecure_external_code_execution when not previously specified" do
    let(:params_hash) do
      hash = { "insecure-external-code-execution" => "allow" }
      hash
    end

    it "updates the setting" do
      expect { action.run }.
        to change(update_config, :insecure_external_code_execution).
        from(nil).to("allow")
    end
  end

  context "updating insecure_external_code_execution when previously specified" do
    let(:update_config) { FactoryBot.create(:update_config, :active, insecure_external_code_execution: "allow") }
    let(:params_hash) do
      hash = { "insecure-external-code-execution" => "deny" }
      hash
    end

    it "updates the setting" do
      expect { action.run }.
        to change(update_config, :insecure_external_code_execution).
        from("allow").to("deny")
    end
  end

  context "updating insecure_external_code_execution when previously specified but no longer specified" do
    let(:update_config) { FactoryBot.create(:update_config, :active, insecure_external_code_execution: "allow") }
    let(:params_hash) { {} }

    it "updates the setting to nil" do
      expect { action.run }.
        to change(update_config, :insecure_external_code_execution).
        from("allow").to(nil)
    end
  end

  context "updating all_registries" do
    context "with no registries config" do
      let(:params_hash) { ActionController::Parameters.new }

      it "does not enable" do
        expect { action.run }.
          not_to change(update_config, :all_registries)
      end

      it "disables if enabled" do
        update_config.update!(all_registries: true)
        expect { action.run }.
          to change(update_config, :all_registries).
          from(true).to(false)
      end
    end

    context "with registries wildcard" do
      let(:params_hash) do
        hash = { "registries" => UpdateConfig::REGISTRY_WILDCARD }
        hash
      end

      it "enables" do
        expect { action.run }.
          to change(update_config, :all_registries).
          from(false).to(true)
      end

      it "does not disable" do
        update_config.update!(all_registries: true)
        expect { action.run }.
          not_to change(update_config, :all_registries)
      end

      it "clears update_config_registries" do
        UpdateConfigRegistry.create(update_config: update_config, registry_name: "registry-1")
        expect { action.run }.
          to change { update_config.update_config_registries.pluck(:registry_name) }.
          from(%w(registry-1)).to([])
      end
    end

    context "with registries array" do
      let(:params_hash) do
        hash = { "registries" => %w(registry-1 registry-2) }
        hash
      end

      it "does not enable" do
        expect { action.run }.
          not_to change(update_config, :all_registries)
      end

      it "disables if enabled" do
        update_config.update!(all_registries: true)
        expect { action.run }.
          to change(update_config, :all_registries).
          from(true).to(false)
      end
    end
  end

  context "maintaining update_config_registries" do
    let(:params_hash) do
      hash = { "registries" => %w(registry-1 registry-2) }
      hash
    end

    it "creates from empty" do
      expect { action.run }.
        to change { update_config.update_config_registries.pluck(:registry_name) }.
        from([]).to(%w(registry-1 registry-2))
    end

    it "amends existing" do
      UpdateConfigRegistry.create(update_config: update_config, registry_name: "registry-1")
      expect { action.run }.
        to change { update_config.update_config_registries.pluck(:registry_name) }.
        from(%w(registry-1)).to(%w(registry-1 registry-2))
    end

    it "deletes existing" do
      UpdateConfigRegistry.create(update_config: update_config, registry_name: "registry-3")
      expect { action.run }.
        to change { update_config.update_config_registries.pluck(:registry_name) }.
        from(%w(registry-3)).to(%w(registry-1 registry-2))
    end
  end

  context "updating enable_beta_ecosystems" do
    let(:params_hash) do
      hash = { "enable-beta-ecosystems" => enable_beta_ecosystems }
      hash
    end
    let(:enable_beta_ecosystems) { true }

    it "updates the setting" do
      expect(MetricsClient).to receive(:increment).
        with("update_config.enable_beta_ecosystems", tags: ["enabled:true"])

      expect { action.run }.
        to change(update_config, :enable_beta_ecosystems).
        from(false).to(true)
    end

    context "when a enable_beta_ecosystems is already set" do
      before { update_config.update!(enable_beta_ecosystems: false) }

      context "and `nil` is provided" do
        let(:enable_beta_ecosystems) { nil }

        it "does not update the setting or increment the Metric" do
          expect(MetricsClient).not_to receive(:increment).
            with("update_config.enable_beta_ecosystems")

          expect { action.run }.
            not_to change(update_config, :enable_beta_ecosystems)
        end
      end

      context "and the key is omitted" do
        let(:params_hash) do
          hash = { "default-reviewers" => {} }
          hash
        end

        it "does not update the setting or increment the Metric" do
          expect(MetricsClient).not_to receive(:increment).
            with("update_config.enable_beta_ecosystems")

          expect { action.run }.
            not_to change(update_config, :enable_beta_ecosystems)
        end
      end
    end
  end

  context "updating cooldown" do
    let(:params_hash) do
      {
        "cooldown" => {
          "default-days" => 7,
          "semver-major-days" => 14,
          "semver-minor-days" => 7,
          "semver-patch-days" => 1,
          "include" => ["dependency1"],
          "exclude" => ["dependency2"],
        },
      }
    end

    it "creates a new cooldown record if it does not exist" do
      expect { action.run }.to change(UpdateConfigCooldown, :count).by(1)
      cooldown = update_config.update_config_cooldown
      expect(cooldown.default_days).to eq(7)
      expect(cooldown.semver_major_days).to eq(14)
      expect(cooldown.semver_minor_days).to eq(7)
      expect(cooldown.semver_patch_days).to eq(1)
      expect(cooldown.include).to eq(["dependency1"])
      expect(cooldown.exclude).to eq(["dependency2"])
    end

    it "updates an existing cooldown record" do
      cooldown = FactoryBot.create(:update_config_cooldown, update_config: update_config, default_days: 3)
      expect { action.run }.not_to change(UpdateConfigCooldown, :count)
      cooldown.reload
      expect(cooldown.default_days).to eq(7)
      expect(cooldown.semver_major_days).to eq(14)
      expect(cooldown.semver_minor_days).to eq(7)
      expect(cooldown.semver_patch_days).to eq(1)
      expect(cooldown.include).to eq(["dependency1"])
      expect(cooldown.exclude).to eq(["dependency2"])
    end

    it "destroys the cooldown record if cooldown details are nil" do
      FactoryBot.create(:update_config_cooldown, update_config: update_config)
      params_hash["cooldown"] = nil
      expect { action.run }.to change(UpdateConfigCooldown, :count).by(-1)
    end
  end

  context "updating exclude_paths" do
    let(:params_hash) do
      hash = { "exclude-paths" => exclude_paths }
      hash
    end

    let(:exclude_paths) { ["test/*", "vendor/**"] }

    it "updates the setting" do
      expect { action.run }.to change(update_config, :exclude_paths).
        from(nil).to(["test/*", "vendor/**"])
    end
  end

  context "when a same exclude_paths value already exists" do
    let(:exclude_paths) { ["test/*", "vendor/**"] }

    before { update_config.update!(exclude_paths: ["test/*", "vendor/**"]) }

    it "does not update the setting" do
      expect { action.run }.
        not_to change(update_config, :exclude_paths)
    end
  end

  context "when exclude-paths key is omiited" do
    let(:params_hash) do
      hash = { "update-schedule" => "weekly" }
      hash
    end

    before { update_config.update!(exclude_paths: ["test/*", "vendor/**"]) }

    it "does not update the setting" do
      expect { action.run }.
        not_to change(update_config, :exclude_paths).
        from(["test/*", "vendor/**"])
    end
  end
end
