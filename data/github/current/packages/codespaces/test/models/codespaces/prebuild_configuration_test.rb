# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesPrebuildConfigurationTest < GitHub::TestCase
  fixtures do
    @simple_repo = create(:repository, owner: create(:organization), from_example: :refs_test)

    GitHub.flipper[:codespaces_prebuilds_new_regions].disable
    GitHub.flipper[:codespaces_local_target_url_valid].disable
  end

  context "branch and repository uniqueness" do
    test "can save when new record has a unique branch, vscs_target and repository combination" do
      create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, vscs_target: :ppe)
      create(:codespace_prebuild_configuration, repository: @simple_repo, branch: "diverge", vscs_target: :ppe)

      refute_nil Codespaces::PrebuildConfiguration.find_by(repository: @simple_repo, branch: @simple_repo.default_branch, vscs_target: :ppe)
      refute_nil Codespaces::PrebuildConfiguration.find_by(repository: @simple_repo, branch: "diverge", vscs_target: :ppe)
    end

    test "can save when new record has a different vscs_target with same repository and branch" do
      create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, vscs_target: :production)
      create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, vscs_target: :ppe)

      refute_nil Codespaces::PrebuildConfiguration.find_by(repository: @simple_repo, branch: @simple_repo.default_branch, vscs_target: :production)
      refute_nil Codespaces::PrebuildConfiguration.find_by(repository: @simple_repo, branch: @simple_repo.default_branch, vscs_target: :ppe)
    end

    test "can save when new record has different repositories and same branch and vscs_target" do
      another_repo = create(:repository, from_example: :simple)
      create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, vscs_target: :ppe)
      create(:codespace_prebuild_configuration, repository: another_repo, branch: @simple_repo.default_branch, vscs_target: :ppe)

      assert_equal Codespaces::PrebuildConfiguration.where(branch: @simple_repo.default_branch).count, 2
    end

    test "does not save when new record does not have a unique vscs_target, branch, devcontainer_path and repository combination" do
      create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, devcontainer_path: "devcontainer/devcontainer.json", vscs_target: :ppe)

      assert_raises_with_message ActiveRecord::RecordInvalid, "Validation failed: Repository and branch 'master' and configuration file 'devcontainer/devcontainer.json' already belong to a configuration on ppe" do
        create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, devcontainer_path: "devcontainer/devcontainer.json", vscs_target: :ppe)
      end
    end

    test "does save when new record has same vscs_target, branch, and repository combination but a different devcontainer_path" do
      create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, devcontainer_path: "devcontainer/devcontainer.json", vscs_target: :ppe)
      create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, devcontainer_path: "custom1/devcontainer.json", vscs_target: :ppe)
      create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, devcontainer_path: nil, vscs_target: :ppe)
      assert_equal Codespaces::PrebuildConfiguration.where(branch: @simple_repo.default_branch).count, 3
    end

    test "treats nil and empty devcontainer_path as same" do
      another_repo = create(:repository, from_example: :simple)
      create(:codespace_prebuild_configuration, repository: another_repo, branch: "master", devcontainer_path: nil, vscs_target: :ppe)
      assert_raises_with_message ActiveRecord::RecordInvalid, "Validation failed: Repository and branch 'master' already belong to a configuration on ppe" do
        create(:codespace_prebuild_configuration, repository: another_repo, branch: "master", devcontainer_path: "", vscs_target: :ppe)
      end
    end
  end

  context "permissions" do
    test "can create a prebuild configuration with permissions granted" do
      configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch)
      assert configuration.permission_granted
      found_configuration = Codespaces::PrebuildConfiguration.where(branch: @simple_repo.default_branch)
      assert T.must(found_configuration.first).permission_granted
    end
  end

  context "branch" do
    test "must exists on the repo" do
      assert_raises_with_message ActiveRecord::RecordInvalid, "Validation failed: Branch 'not-a-branch' does not exist on the repository" do
        configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: "not-a-branch")
      end
    end
  end

  context "#vscs_target" do
    test "is converted to a symbol" do
      configuration = build(:codespace_prebuild_configuration)

      configuration.vscs_target = "production"
      assert_equal :production, configuration.vscs_target

      configuration.vscs_target = "local"
      assert_equal :local, configuration.vscs_target
    end

    test "an empty vscs target is set to production and that db record isn't nil" do
      configuration = create(:codespace_prebuild_configuration)
      assert_equal :production, configuration.vscs_target
      configuration_nil = Codespaces::PrebuildConfiguration.find_by(repository: configuration.repository, branch: configuration.branch, vscs_target: nil)
      assert_nil configuration_nil
    end

    test "when vscs target is set to nil then it is still stored as production in db" do
      configuration = create(:codespace_prebuild_configuration, vscs_target: nil)
      assert_equal :production, configuration.vscs_target
      configuration = Codespaces::PrebuildConfiguration.find_by(repository: configuration.repository, branch: configuration.branch, vscs_target: :production)
      refute_nil configuration
    end

    test "an invalid vscs target raises an error" do
      configuration = build(:codespace_prebuild_configuration, vscs_target: "something")
      assert_raises ActiveRecord::RecordInvalid, "Vscs target is not included in the list" do
        configuration.save!
      end
    end
  end

  context "#vscs_target_url" do
    test "is required for the local target" do
      local_configuration = build(
        :codespace_prebuild_configuration,
        vscs_target: :local,
      )

      local_configuration.vscs_target_url = "http://localhost.example.com/"
      assert_predicate local_configuration, :valid?

      local_configuration.vscs_target_url = nil
      refute_predicate local_configuration, :valid?
      assert_includes local_configuration.errors.full_messages, "Vscs target url must be present when vscs_target is local"
    end

    test "is forbidden for non-local targets" do
      production_configuration = build(
        :codespace_prebuild_configuration,
        vscs_target: :production,
      )

      production_configuration.vscs_target_url = nil
      assert_predicate production_configuration, :valid?

      production_configuration.vscs_target_url = "http://localhost.example.com"
      refute_predicate production_configuration, :valid?
      assert_includes production_configuration.errors.full_messages, "Vscs target url must be blank when vscs_target is not local"
    end

    test "throws error if vscs target is local and vscs target url is invalid" do
      GitHub.flipper[:codespaces_local_target_url_valid].enable
      prebuild_config = build(:codespace_prebuild_configuration, vscs_target: :local, vscs_target_url: "http://localhost:8080")
      refute_predicate prebuild_config, :valid?
      assert_includes prebuild_config.errors[:vscs_target_url], "must be a valid local target URL"
    end

    test "creates record if vscs target is local and vscs target url is valid" do
      GitHub.flipper[:codespaces_local_target_url_valid].enable
      prebuild_config = build(:codespace_prebuild_configuration, vscs_target: :local, vscs_target_url: "https://online.dev.core.vsengsaas.visualstudio.com")
      assert_predicate prebuild_config, :valid?
      assert_equal prebuild_config.vscs_target, :local
    end
  end

  context "#locations" do
    context "as geos" do
      test "can delete a location" do
        geos = %w[
          UsWest
          UsEast
          EuropeWest
        ]
        configuration = create(:codespace_prebuild_configuration, with_geos: geos)
        assert_difference -> { configuration.locations.count }, -1 do
          configuration.locations.delete(configuration.locations.first)
        end
      end

      test "can't delete all locations" do
        geos = %w[
          UsWest
          UsEast
          EuropeWest
        ]
        configuration = create(:codespace_prebuild_configuration, with_geos: geos)
        configuration.locations.delete_all

        assert_raises ActiveRecord::RecordInvalid, "Locations You must select at least one region" do
          configuration.save!
        end
      end

      test "can retrieve multiple locations" do
        configuration = create(:codespace_prebuild_configuration, with_geos: %w[UsWest UsEast])
        assert_equal configuration.locations.length, 2
      end

      test "can add same location to different prebuild configurations" do
        create(:codespace_prebuild_configuration, with_geos: ["UsWest"])
        create(:codespace_prebuild_configuration, with_geos: ["UsWest"])
      end

      test "deleting prebuild configurations delete its locations" do
        configuration = create(:codespace_prebuild_configuration, with_geos: %w[UsWest UsEast])
        location_id = configuration.locations.first.id
        configuration.destroy
        assert_nil Codespaces::PrebuildConfigurationLocation.find_by(id: location_id)
      end
    end
  end

  context "#targeted_geos" do
    test "respects feature flagged geo rollouts" do
      rollout_feature_flag = :codespaces_geo_rollout_eastus
      GitHub.flipper[rollout_feature_flag].enable
      geo = Codespaces::Locations::Geo.find("UsEast")
      geo.stubs(:rollout_feature_flag).returns(rollout_feature_flag)
      geo.stubs(:previous_geo_id).returns("UsWest")

      configuration = create(:codespace_prebuild_configuration, with_geos: %w[UsWest UsEast])

      GitHub.flipper[rollout_feature_flag].disable

      assert_equal ["UsWest"], configuration.targeted_geos.map(&:id)
    end
  end

  context "#targets_all_geos" do
    test "respects feature flagged geo rollouts" do
      # UsEast initially disabled when the prebuild was created targeting all geos...
      rollout_feature_flag = :codespaces_geo_rollout_eastus
      GitHub.flipper[rollout_feature_flag].disable
      geo = Codespaces::Locations::Geo.find("UsEast")
      geo.stubs(:rollout_feature_flag).returns(rollout_feature_flag)
      geo.stubs(:previous_geo_id).returns("UsWest")

      configuration = create(:codespace_prebuild_configuration, locations: [], all_geos: true)

      assert configuration.targets_all_geos?

      # ...but then enabled later
      GitHub.flipper[rollout_feature_flag].enable

      refute configuration.targets_all_geos?
    end
  end

  context "#trigger" do
    test "trigger defaults to 1(Push)" do
      configuration = create(:codespace_prebuild_configuration)
      assert_equal configuration.trigger.to_sym, Codespaces::PrebuildConfiguration::DEFAULT_TRIGGER
      assert_predicate configuration, :valid?
    end

    test "can save trigger value" do
      configuration = create(:codespace_prebuild_configuration, trigger: :push)
      assert_equal configuration.trigger.to_sym, :push
    end
  end

  context "build_initial_locations" do
    context "as geos" do
      test "builds locations with given locations" do
        configuration = Codespaces::PrebuildConfiguration.new(
          vscs_target: "production",
          repository: @simple_repo,
          branch: @simple_repo.default_branch
        )

        geos = %w[
          EuropeWest
          SoutheastAsia
        ]

        configuration.build_initial_locations(locations: geos)
        configuration.save!
        assert_same_elements configuration.locations.map(&:geo), geos
      end

      test "builds all available locations when all is true" do
        configuration = Codespaces::PrebuildConfiguration.new(
          vscs_target: "production",
          repository: @simple_repo,
          branch: @simple_repo.default_branch
        )

        configuration.build_initial_locations(all: true)
        configuration.save!
        assert_same_elements configuration.locations.map(&:geo), Codespaces::Locations::Geo.where(vscs_target: Codespaces::Vscs.default_target).map(&:id)
      end

      test "geo entries still store regions" do
        configuration = Codespaces::PrebuildConfiguration.new(
          vscs_target: "production",
          repository: @simple_repo,
          branch: @simple_repo.default_branch
        )

        configuration.build_initial_locations(all: true)
        configuration.save!
        assert_same_elements configuration.locations.map(&:location), Codespaces::Locations::Geo.public.map { |geo| geo.primary_region.id }
      end
    end
  end

  context "update_locations" do
    context "with geos" do
      test "adds new locations" do
        initial_locations = ["UsWest"]
        configuration = create(:codespace_prebuild_configuration, with_geos: initial_locations)
        new_locations = %w[UsWest UsEast]
        configuration.update_locations(all: false, locations: new_locations)
        assert_same_elements configuration.locations.reload.map(&:geo), new_locations
      end

      test "removes existing locations" do
        initial_locations = %w[UsWest UsEast]
        configuration = create(:codespace_prebuild_configuration, with_geos: initial_locations)
        new_locations = ["UsWest"]
        configuration.update_locations(all: false, locations: new_locations)
        assert_same_elements configuration.locations.reload.map(&:geo), new_locations
      end

      test "leaves existing locations the same" do
        initial_locations = %w[UsWest UsEast]
        configuration = create(:codespace_prebuild_configuration, with_geos: initial_locations)
        configuration.update_locations(all: false, locations: initial_locations)
        assert_same_elements configuration.locations.reload.map(&:geo), initial_locations
      end

      test "handles a combination of removing and adding" do
        initial_locations = %w[UsWest UsEast]
        configuration = create(:codespace_prebuild_configuration, with_geos: initial_locations)
        new_locations = %w[UsWest EuropeWest]
        configuration.update_locations(all: false, locations: new_locations)
        assert_same_elements configuration.locations.reload.map(&:geo), new_locations
      end

      test "stores regions when geos are updated" do
        initial_locations = ["UsWest"]
        configuration = create(:codespace_prebuild_configuration, with_geos: initial_locations)
        new_locations = %w[EuropeWest UsEast]
        configuration.update_locations(all: false, locations: new_locations)

        regions_stored = %w[WestEurope EastUs]
        assert_same_elements configuration.locations.reload.map(&:location), regions_stored
      end
    end
  end

  context "build_delivery_times" do
    test "builds schedules with given delivery times" do
      configuration = Codespaces::PrebuildConfiguration.new(
        vscs_target: "production",
        repository: @simple_repo,
        branch: @simple_repo.default_branch
      )

      delivery_days = %w[Monday Wednesday]

      delivery_times = ["5:00 AM", "5:30 AM"]

      locations = %w[
        EuropeWest
        SoutheastAsia
      ]

      configuration.build_initial_locations(locations: locations)
      configuration.build_delivery_times(
        delivery_days: delivery_days,
        delivery_times: delivery_times,
        time_zone_name: "America/New_York")
      configuration.save!
      assert_same_elements configuration.schedules.map(&:delivery_day).uniq, delivery_days
      assert_same_elements configuration.schedules.map(&:delivery_time).uniq, delivery_times
      assert_equal configuration.schedules.pluck(:time_zone_name).first, "America/New_York"
    end

    test "can't save schedule with invalid schedule values" do
      configuration = Codespaces::PrebuildConfiguration.new(
        vscs_target: "production",
        repository: @simple_repo,
        branch: @simple_repo.default_branch
      )

      locations = %w[
        EuropeWest
        SoutheastAsia
      ]

      configuration.build_initial_locations(locations: locations)
      configuration.build_delivery_times(
        delivery_days: [],
        delivery_times: [],
        time_zone_name: "America/New_York")
      configuration.trigger = :schedule

      assert_raises ActiveRecord::RecordInvalid, "'Scheduled' is not a valid trigger without selecting a day, time, and time zone" do
        configuration.save!
      end
    end
  end

  context "update_delivery_times" do
    test "removes exist schedules and creates new" do
      configuration = Codespaces::PrebuildConfiguration.new(
        vscs_target: "production",
        repository: @simple_repo,
        branch: @simple_repo.default_branch
      )

      delivery_days = %w[Monday Wednesday]

      delivery_times = ["5:00 AM", "5:30 AM"]

      locations = %w[
        EuropeWest
        SoutheastAsia
      ]

      configuration.build_initial_locations(locations: locations)
      configuration.build_delivery_times(
        delivery_days: delivery_days,
        delivery_times: delivery_times,
        time_zone_name: "America/New_York")
      configuration.save!

      assert_same_elements configuration.schedules.map(&:delivery_day).uniq, delivery_days
      assert_same_elements configuration.schedules.map(&:delivery_time).uniq, delivery_times
      assert_equal configuration.schedules.pluck(:time_zone_name).first, "America/New_York"

      # Update schedule
      delivery_days_update = %w[Tuesday Thursday]
      delivery_times_update = ["10:00 AM"]

      configuration.update_delivery_times(
        new_trigger: "schedule",
        delivery_days: delivery_days_update,
        delivery_times: delivery_times_update,
        time_zone_name: "America/New_York"
      )

      assert_same_elements configuration.schedules.map(&:delivery_day).uniq, delivery_days_update
      assert_same_elements configuration.schedules.map(&:delivery_time).uniq, delivery_times_update

      refute_same_elements configuration.schedules.map(&:delivery_day).uniq, delivery_days
      refute_same_elements configuration.schedules.map(&:delivery_day).uniq, delivery_days
    end
  end

  context "latest workflow_run" do
    context "the workflow has been created but not run" do
      test "returns correct fields" do
        configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, workflow_run_times: 0)
        assert_nil configuration.latest_workflow_run
      end
    end

    context "the workflow has been run" do
      test "returns correct fields" do
        configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, workflow_run_times: 1)
        assert configuration.latest_workflow_run
      end
    end

    context "#has_ran?" do
      test  "return true if latest_workflow_run exist" do
        configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, workflow_run_times: 1)
        assert configuration.has_ran?
      end

      test  "return false if latest_workflow_run is nil" do
        configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, workflow_run_times: 0)
        refute configuration.has_ran?
      end
    end
  end

  context "#instrument_event" do
    test "raises error if invalid event type is given" do
      assert_raises ArgumentError, "Invalid audit log event type: :invalid" do
        configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch)
        configuration.instrument_event(type: :invalid, user: create(:user))
      end
    end

    test "creates an audit log event for CREATE" do
      events = subscribe "prebuild_configuration.create"

      user = create(:user)
      configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch)
      configuration.instrument_event(type: Codespaces::PrebuildConfiguration::INSTRUMENT_CREATE, user: user)

      expected_payload = {
        branch: configuration.branch,
        vscs_target: configuration.vscs_target,
        locations: configuration.region_names,
        trigger: Codespaces::PrebuildConfiguration::DEFAULT_TRIGGER.to_s,
        repository: configuration.repository.nwo,
        repository_id: configuration.repository.id,
        public_repo: configuration.repository.public?,
        org: configuration.owner.name,
        org_id: configuration.owner.id,
        user: user.login,
        user_id: user.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "creates an audit log event for UPDATE" do
      events = subscribe "prebuild_configuration.update"

      user = create(:user)
      configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch)
      configuration.instrument_event(type: Codespaces::PrebuildConfiguration::INSTRUMENT_UPDATE, user: user)

      expected_payload = {
        branch: configuration.branch,
        vscs_target: configuration.vscs_target,
        locations: configuration.region_names,
        trigger: Codespaces::PrebuildConfiguration::DEFAULT_TRIGGER.to_s,
        repository: configuration.repository.nwo,
        repository_id: configuration.repository.id,
        public_repo: configuration.repository.public?,
        org: configuration.owner.name,
        org_id: configuration.owner.id,
        user: user.login,
        user_id: user.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "creates an audit log event for DESTROY" do
      events = subscribe "prebuild_configuration.destroy"

      user = create(:user)
      configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch)
      configuration.instrument_event(type: Codespaces::PrebuildConfiguration::INSTRUMENT_DESTROY, user: user)

      expected_payload = {
        branch: configuration.branch,
        vscs_target: configuration.vscs_target,
        locations: configuration.region_names,
        trigger: Codespaces::PrebuildConfiguration::DEFAULT_TRIGGER.to_s,
        repository: configuration.repository.nwo,
        repository_id: configuration.repository.id,
        public_repo: configuration.repository.public?,
        org: configuration.owner.name,
        org_id: configuration.owner.id,
        user: user.login,
        user_id: user.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "creates an audit log event for RUN_TRIGGERED" do
      events = subscribe "prebuild_configuration.run_triggered"

      user = create(:user)
      configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch)
      configuration.instrument_event(type: Codespaces::PrebuildConfiguration::INSTRUMENT_RUN_TRIGGERED, user: user)

      expected_payload = {
        branch: configuration.branch,
        vscs_target: configuration.vscs_target,
        locations: configuration.region_names,
        trigger: Codespaces::PrebuildConfiguration::DEFAULT_TRIGGER.to_s,
        repository: configuration.repository.nwo,
        repository_id: configuration.repository.id,
        public_repo: configuration.repository.public?,
        org: configuration.owner.name,
        org_id: configuration.owner.id,
        user: user.login,
        user_id: user.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "#destroy_prebuilds" do
    test  "finds and destroys prebuild configurations from branch and repo" do
      @simple_repo = create(:repository, owner: create(:organization), from_example: :simple)

      configuration_1 = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, vscs_target: :ppe)
      configuration_2 = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, vscs_target: :production)
      ids = [configuration_1.id, configuration_2.id]

      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).twice
      Codespaces::PrebuildConfiguration.destroy_prebuilds(branch: @simple_repo.default_branch, repository: @simple_repo)

      assert_empty Codespaces::PrebuildConfiguration.where(id: ids)
    end
  end

  context "#destroy_with_template_clean_up" do
    test "queues the DeletePrebuildTemplatesJob and destroy the configuration" do
      configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch)
      prebuild_configuration_id = configuration.id

      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).with(
        branch: @simple_repo.default_branch,
        locations: configuration.region_names,
        repository_id: @simple_repo.id,
        vscs_target: :production,
        vscs_target_url: nil,
        devcontainer_path: nil,
        configuration_id: prebuild_configuration_id,
      )

      configuration.destroy_with_template_clean_up

      assert_nil Codespaces::PrebuildConfiguration.find_by(id: prebuild_configuration_id)
    end
  end

  context "#toggle_state" do
    test "if state is enabled then update to disabled" do
      configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, state: :enabled)

      configuration.toggle_state
      configuration.save

      assert_equal Codespaces::PrebuildConfiguration.find(configuration.id).state.to_sym, :disabled
    end

    test "if state is disabled then update to enabled" do
      configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch, state: :disabled)

      configuration.toggle_state
      configuration.save

      assert_equal Codespaces::PrebuildConfiguration.find(configuration.id).state.to_sym, :enabled
    end
  end

  context "actors to notify" do
    test "builds empty actors to notify when no teams or users are given" do
      configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch)
      configuration.build_actors_to_notify
      configuration.save!

      assert_empty configuration.actors_to_notify
    end

    test "builds actors to notify with given users and teams" do
      user_1 = create(:user)
      user_2 = create(:user)
      user_3 = create(:user)
      user_4 = create(:user)
      user_logins = [user_1.login, user_2.login, user_3.login, user_4.login]

      team_1 = create(:team, organization: @simple_repo.owner)
      team_2 = create(:team, organization: @simple_repo.owner)
      team_slugs = [team_1.slug, team_2.slug]

      configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch)
      configuration.build_actors_to_notify(user_logins: user_logins, team_slugs: team_slugs)
      configuration.save!

      assert_equal configuration.actors_to_notify.count, 6
      assert_equal configuration.actors_to_notify.where(owner_type: :User).map(&:owner_id).sort, [user_1.id, user_2.id, user_3.id, user_4.id].sort
      assert_equal configuration.actors_to_notify.where(owner_type: :Team).map(&:owner_id).sort, [team_1.id, team_2.id].sort
      assert_equal configuration.actors_to_notify.pluck(:codespace_prebuild_configuration_id).first, configuration.id
    end

    test "removes existing actors to notify and creates new on update" do
      user_1 = create(:user)
      user_2 = create(:user)
      user_3 = create(:user)
      user_logins = [user_1.login, user_2.login, user_3.login]

      team_1 = create(:team, organization: @simple_repo.owner)
      team_2 = create(:team, organization: @simple_repo.owner)
      team_slugs = [team_1.slug, team_2.slug]

      configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch)
      configuration.build_actors_to_notify(user_logins: user_logins, team_slugs: team_slugs)
      configuration.save!

      assert_equal configuration.actors_to_notify.count, 5
      assert_equal configuration.actors_to_notify.where(owner_type: :User).map(&:owner_id).sort, [user_1.id, user_2.id, user_3.id].sort
      assert_equal configuration.actors_to_notify.where(owner_type: :Team).map(&:owner_id).sort, [team_1.id, team_2.id].sort

      # Update Users to notify
      user_4 = create(:user)
      user_5 = create(:user)
      user_logins_updated = [user_4.login, user_5.login]

      team_3 = create(:team, organization: @simple_repo.owner)
      team_slugs_updated = [team_1.slug, team_3.slug]

      configuration.update_actors_to_notify(user_logins: user_logins_updated, team_slugs: team_slugs_updated)
      configuration.save!

      refute_same_elements configuration.actors_to_notify.where(owner_type: :User).map(&:owner_id).sort, [user_1.id, user_2.id, user_3.id].sort
      assert_same_elements configuration.actors_to_notify.where(owner_type: :User).map(&:owner_id).sort, [user_4.id, user_5.id].sort
      refute_same_elements configuration.actors_to_notify.where(owner_type: :Team).map(&:owner_id).sort, [team_1.id, team_2.id].sort
      assert_same_elements configuration.actors_to_notify.where(owner_type: :Team).map(&:owner_id).sort, [team_1.id, team_3.id].sort
    end

    test "users_to_notify returns list of users that map to the ids of users in actors_to_notify" do
      user_1 = create(:user)
      user_2 = create(:user)
      user_3 = create(:user)
      user_logins = [user_1.login, user_2.login, user_3.login]

      configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch)
      configuration.build_actors_to_notify(user_logins: user_logins)
      configuration.save!

      user_profiles = configuration.users_to_notify

      assert_equal user_profiles.map(&:id).sort, [user_1.id, user_2.id, user_3.id].sort
    end

    test "teams_to_notify returns list of users that map to the ids of teams in actors_to_notify" do
      user_1 = create(:user)
      user_2 = create(:user)
      user_3 = create(:user)
      user_logins = [user_1.login, user_2.login, user_3.login]

      configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch)
      configuration.build_actors_to_notify(user_logins: user_logins)
      configuration.save!

      user_profiles = configuration.users_to_notify

      assert_equal user_profiles.map(&:id).sort, [user_1.id, user_2.id, user_3.id].sort
    end

    test "deleting configuration deletes actors to notify" do
      user_1 = create(:user)
      user_2 = create(:user)
      user_3 = create(:user)
      user_logins = [user_1.login, user_2.login, user_3.login]

      team_1 = create(:team, organization: @simple_repo.owner)
      team_2 = create(:team, organization: @simple_repo.owner)
      team_slugs = [team_1.slug, team_2.slug]

      configuration = create(:codespace_prebuild_configuration, repository: @simple_repo, branch: @simple_repo.default_branch)
      configuration.build_actors_to_notify(user_logins: user_logins, team_slugs: team_slugs)
      configuration.save!

      refute_nil Codespaces::PrebuildConfiguration.find(configuration.id)
      refute_nil Codespaces::PrebuildNotificationActor.find_by(codespace_prebuild_configuration_id: configuration.id)

      configuration.destroy

      assert_nil Codespaces::PrebuildConfiguration.find_by(id: configuration.id)
      assert_nil Codespaces::PrebuildNotificationActor.find_by(codespace_prebuild_configuration_id: configuration.id)
      assert_nil Codespaces::PrebuildNotificationActor.find_by(owner_id: user_1.id)
      assert_nil Codespaces::PrebuildNotificationActor.find_by(owner_id: user_2.id)
      assert_nil Codespaces::PrebuildNotificationActor.find_by(owner_id: user_3.id)
      assert_nil Codespaces::PrebuildNotificationActor.find_by(owner_id: team_1.id)
      assert_nil Codespaces::PrebuildNotificationActor.find_by(owner_id: team_2.id)
    end
  end

  context "#maximum_template_versions" do
    test "maximum_template_versions defaults to 2" do
      configuration = create(:codespace_prebuild_configuration)
      assert_equal configuration.maximum_template_versions, Codespaces::PrebuildConfiguration::DEFAULT_MAX_VERSIONS
    end

    test "can save maximum_template_versions with valid value" do
      configuration = create(:codespace_prebuild_configuration, maximum_template_versions: 2)
      assert_equal configuration.maximum_template_versions, 2
    end

    test "can't save maximum_template_versions with invalid value" do
      assert_raises ActiveRecord::RecordInvalid, "Template version count cannot be smaller than 1." do
        configuration = create(:codespace_prebuild_configuration, maximum_template_versions: 0)
      end
    end
  end

  context "#devcontainer_path" do
    test "stores nil devcontainer_path in db if devcontainer path doesn't exist" do
      configuration = create(:codespace_prebuild_configuration)
      assert_nil configuration.devcontainer_path
    end

    test "stores default devcontainer_path in db if not already defined" do
      @simple_repo.refs.find(@simple_repo.default_branch).append_commit({ message: "add devcontainer json file", committer: @simple_repo.owner }, @simple_repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", "{}")
        files.add(".devcontainer/another_devcontainer.json", "{}")
      end

      configuration = create(:codespace_prebuild_configuration, branch: @simple_repo.default_branch, repository: @simple_repo)
      assert_equal configuration.devcontainer_path, ".devcontainer/devcontainer.json"
    end

    test "does not replace devcontainer path with default if it is set to another path" do
      @simple_repo.refs.find(@simple_repo.default_branch).append_commit({ message: "add devcontainer json file", committer: @simple_repo.owner }, @simple_repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", "{}")
        files.add(".devcontainer/another_devcontainer.json", "{}")
      end

      configuration = create(:codespace_prebuild_configuration, branch: @simple_repo.default_branch, repository: @simple_repo)
      configuration.update(devcontainer_path: ".devcontainer/another_devcontainer.json")

      assert_equal configuration.devcontainer_path, ".devcontainer/another_devcontainer.json"
    end
  end
end
