# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class RepositoryDependencyUpdateTest < GitHub::TestCase
  include DependabotGithubAppHelper

  fixtures do
    # Set up the dependabot app
    make_trusted_oauth_apps_owner
    @dependabot_app = create(:dependabot_integration)

    @repository = create(:repository, from_example: :pull_request_fork)

    @pull_request = create(:pull_request, repository: @repository)

    @dependabot_install = @dependabot_app.install_on(
      @repository.owner,
      repositories: [],
      installer: @repository.owner,
      entry_point: :test_case
    ).installation

    @rails_vulnerability = create :published_vulnerability, with_ranges: 0
    @rails_vulnerable_version = create :vulnerable_version_range,
                                         vulnerability: @rails_vulnerability,
                                         affects:     "rails",
                                         requirements: "< 4.1.0",
                                         fixed_in: "4.1.0",
                                         ecosystem: "RubyGems"
    @rails_vulnerability.reload

    @requested_update = create(:repository_dependency_update,
                               :requested,
                               repository: @repository,
                               manifest_path: "Gemfile.lock",
                               package_name: "rails")

    @completed_update = create(:repository_dependency_update,
                               :completed,
                               repository: @repository,
                               pull_request: @pull_request,
                               manifest_path: "Gemfile.lock",
                               package_name: "rails")

    @errored_update   = create(:repository_dependency_update,
                               :errored,
                               repository: @repository,
                               manifest_path: "Gemfile.lock",
                               package_name: "rails")
  end

  setup do
    if GitHub.enterprise?
      GitHub.stubs(
        dependabot_enabled?: true,
        dependency_graph_enabled?: true,
        ghe_content_analysis_enabled?: true,
      )
    end
    reset_dependabot_github_app_memoization
    @repository.enable_vulnerability_updates(actor: @repository.owner)
  end

  def update_for(manifest_path)
    build(:repository_dependency_update, manifest_path: manifest_path)
  end

  def create_completed_update
    repository = create(:repository, from_example: :pull_request_fork)
    pull_request = create(:pull_request, repository: repository)
    create(:repository_dependency_update,
           repository: repository,
           state: :complete,
           pull_request: pull_request)
  end

  context "defaults" do
    test "state is requested" do
      assert_equal "requested", RepositoryDependencyUpdate.new.state
    end

    test "reason is vulnerability" do
      assert_equal "vulnerability", RepositoryDependencyUpdate.new.reason
    end

    test "trigger_type is manual" do
      assert_equal "manual", RepositoryDependencyUpdate.new.trigger_type
    end

    test "dry_run is false" do
      refute RepositoryDependencyUpdate.new.dry_run
    end

    test "retry is false" do
      refute RepositoryDependencyUpdate.new.retry
    end
  end

  context "validation" do
    test "must have a repository" do
      assert_predicate @requested_update, :valid?
      @requested_update.repository = nil
      refute_predicate @requested_update, :valid?
    end

    test "must have a manifest_path" do
      assert_predicate @requested_update, :valid?
      @requested_update.manifest_path = nil
      refute_predicate @requested_update, :valid?
    end

    test "must not have an unsupported manifest path on creation" do
      new_update = build(:repository_dependency_update,
                         :requested,
                         repository: @repository,
                         manifest_path: "Gemfile",
                         package_name: "rails")

      refute_predicate new_update, :valid?
    end

    test "must have a package_name" do
      assert_predicate @requested_update, :valid?
      @requested_update.package_name = nil
      refute_predicate @requested_update, :valid?
    end

    test "requested updates cannot have a pull request assigned" do
      assert_predicate @requested_update, :valid?
      @requested_update.pull_request = @pull_request
      refute_predicate @requested_update, :valid?
    end

    test "requested updates cannot have an error title set" do
      assert_predicate @requested_update, :valid?
      @requested_update.error_title = "Something went wrong."
      refute_predicate @requested_update, :valid?
    end

    test "requested updates cannot have an error body set" do
      assert_predicate @requested_update, :valid?
      @requested_update.error_body = "The Gemfile.lock was malformed."
      refute_predicate @requested_update, :valid?
    end

    test "vulnerability updates must have an alert assigned on creation" do
      new_update = build(:repository_dependency_update,
                         :requested,
                         repository: @repository,
                         repository_vulnerability_alert: nil,
                         manifest_path: "Gemfile.lock",
                         package_name: "rails")

      refute_predicate new_update, :valid?
    end

    test "vulnerability updates may have their alert removed after creation" do
      assert_predicate @requested_update, :valid?
      @requested_update.update(repository_vulnerability_alert: nil)
      assert_predicate @requested_update, :valid?
    end

    test "completed updates must have a pull request" do
      assert_predicate @completed_update, :valid?
      @completed_update.pull_request = nil
      refute_predicate @completed_update, :valid?
    end

    test "completed updates must have a pull request from the same parent repository" do
      assert_predicate @completed_update, :valid?
      @completed_update.repository = create(:repository)
      refute_predicate @completed_update, :valid?
    end

    test "an errored update must have an error title set" do
      assert_predicate @errored_update, :valid?
      @errored_update.error_title = nil
      refute_predicate @errored_update, :valid?
    end

    test "an errored update must have an error body set" do
      assert_predicate @errored_update, :valid?
      @errored_update.error_body = nil
      refute_predicate @errored_update, :valid?
    end

    test "an errored update cannot have a pull request set" do
      assert_predicate @errored_update, :valid?
      @errored_update.pull_request = @pull_request
      refute_predicate @errored_update, :valid?
    end

    test "a pull request may more than one completed dependency update object" do
      new_update = create(:repository_dependency_update,
                          :completed,
                          repository: @repository,
                          pull_request: @pull_request,
                          manifest_path: "Gemfile.lock",
                          package_name: "rails")

      assert_predicate new_update, :valid?
    end
  end

  context "instrumentation" do
    test "creation is tracked" do
      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = create(:repository_dependency_update,
                      :requested,
                      repository: @repository,
                      manifest_path: "Gemfile.lock",
                      package_name: "rails")


      expected_payload = {
        repository_dependency_update: update,
        repository: @repository,
      }

      assert_equal expected_payload, actual_payload
    end

    test "completion is tracked" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.complete") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = create(:repository_dependency_update,
                      :requested,
                      repository: @repository,
                      manifest_path: "Gemfile.lock",
                      package_name: "rails")

      expected_payload = {
        repository_dependency_update: update,
        repository: @repository,
        pull_request: @pull_request,
      }

      expected_tags = [
        "trigger:manual",
        "package_manager:bundler",
        "retry:false"
      ]

      update.mark_as_complete(pull_request: @pull_request)

      assert_equal expected_payload, actual_payload

      completed_increments = GitHub.dogstats.increments("repository_dependency_update.completed", tags: expected_tags)
      assert_equal 1, completed_increments.length
    end

    test "failure is tracked" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.errored") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = create(:repository_dependency_update,
                      :requested,
                      repository: @repository,
                      manifest_path: "Gemfile.lock",
                      package_name: "rails")

      expected_payload = {
        repository_dependency_update: update,
        repository: @repository,
      }

      expected_tags = [
        "trigger:manual",
        "package_manager:bundler",
        "retry:false",
        "viable_update:false",
        "timed_out:false",
      ]

      update.mark_as_errored(title: "Cannot open pod bay doors.",
                             body: "I'm sorry, Dave. I'm afraid I can't do that.",
                             type: "update_not_possible")

      assert_equal expected_payload, actual_payload

      errored_increments = GitHub.dogstats.increments("repository_dependency_update.errored", tags: expected_tags)
      assert_equal 1, errored_increments.length
    end

    test "update time distributions are tracked" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      Timecop.freeze do
        create(:repository_dependency_update, :requested, repository: @repository, created_at: 10.minutes.ago)
          .mark_as_complete(pull_request: @pull_request)
      end

      expected_tags = [
        "package_manager:bundler",
        "retry:false",
        "state:complete",
        "trigger:manual",
        "viable_update:true",
      ]

      operations = GitHub.dogstats.distributions("repository_dependency_update.dist.duration", tags: expected_tags)

      assert_equal 1, operations.length
      assert_in_delta 10.minutes.in_seconds, operations.first.value, 1.second
    end

    test "updates that do not change state are not tracked" do
      complete_tracked = T.let(false, T::Boolean)
      GlobalInstrumenter.subscribe("repository_dependency_update.complete") do |*_args|
        complete_tracked = true
      end

      error_tracked = T.let(false, T::Boolean)
      GlobalInstrumenter.subscribe("repository_dependency_update.errored") do |*_args|
        error_tracked = true
      end

      update = create(:repository_dependency_update,
                      :requested,
                      repository: @repository,
                      manifest_path: "Gemfile.lock",
                      package_name: "rails")

      update.update!(manifest_path: "package.json")

      assert_predicate update, :requested?
      refute complete_tracked
      refute error_tracked
    end

    test "completion is not redundantly tracked for an already-completed update" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      complete_tracked = T.let(false, T::Boolean)
      GlobalInstrumenter.subscribe("repository_dependency_update.complete") do |*_args|
        complete_tracked = true
      end

      assert_predicate @completed_update, :complete?
      assert_equal @pull_request, @completed_update.pull_request

      @pull_request.close
      new_pull_request = create(:pull_request, repository: @repository)
      @completed_update.mark_as_complete(pull_request: new_pull_request)

      @completed_update.reload

      assert_predicate @completed_update, :complete?
      assert_equal new_pull_request, @completed_update.pull_request

      assert_equal 0, GitHub.dogstats.distributions("repository_dependency_update.dist.duration").count
      assert_equal 0, GitHub.dogstats.increments("repository_dependency_update.completed").count
      refute complete_tracked
    end
  end

  context "#dry_run?" do
    %i{
      manual
      install
      scan
      push
    }.each do |trigger_type|
      test "is false by default when the trigger_type is '#{trigger_type}''" do
        update = create(:repository_dependency_update,
                        :requested,
                        repository: @repository,
                        trigger_type: trigger_type)

        refute update.dry_run?
      end
    end

    test "is true when the trigger type is dry_run" do
      update = build(:repository_dependency_update,
                      :requested,
                      repository: @repository,
                      trigger_type: :dry_run)
      update.save(validate: false)

      assert update.dry_run?
    end

    %i{
      manual
      install
      scan
      push
      dry_run
    }.each do |trigger_type|
      test "is true for '#{trigger_type}' when the dry_run flag is set" do
        update = build(:repository_dependency_update,
                        :requested,
                        repository: @repository,
                        trigger_type: trigger_type,
                        dry_run: true)
        update.save(validate: false)

        assert update.dry_run?
      end
    end
  end

  context "#retry?" do
    test "is set to false for the first dependency update created for an alert" do
      @alert = create(:repository_vulnerability_alert, repository: @repository)

      @update = create(:repository_dependency_update, repository: @repository,
                                                      repository_vulnerability_alert: @alert)

      refute_predicate @update, :retry?
    end

    test "is set to true for all subsequent dependency updates created for an alert" do
      @alert = create(:repository_vulnerability_alert, repository: @repository)

      @update = create(:repository_dependency_update, repository: @repository,
                                                      repository_vulnerability_alert: @alert)

      refute_predicate @update, :retry?

      @first_retry = create(:repository_dependency_update, repository: @repository,
                                                           repository_vulnerability_alert: @alert)

      assert_predicate @first_retry, :retry?

      @second_retry = create(:repository_dependency_update, repository: @repository,
                                                            repository_vulnerability_alert: @alert)

      assert_predicate @first_retry, :retry?
    end

    test "is not mutated when a record is eddited" do
      @alert = create(:repository_vulnerability_alert, repository: @repository)

      @update = create(:repository_dependency_update, repository: @repository,
                                                      repository_vulnerability_alert: @alert)

      refute_predicate @update, :retry?

      @first_retry = create(:repository_dependency_update, repository: @repository,
                                                           repository_vulnerability_alert: @alert)

      assert_predicate @first_retry, :retry?

      @update.mark_as_errored(title: "This is fine.", body: "Fire everywhere.", type: "fine")

      refute_predicate @update.reload, :retry?
    end
  end

  context "::visible" do
    test "excludes rows with trigger_type of dry_run" do
      dry_run_update = build(:repository_dependency_update,
                             :requested,
                             repository: @repository,
                             trigger_type: :dry_run)
      dry_run_update.save(validate: false)

      refute RepositoryDependencyUpdate.visible.exists?(dry_run_update.id)
    end

    test "excludes rows with dry_run set to true" do
      dry_run_update = create(:repository_dependency_update,
                              :requested,
                              :dry_run,
                              repository: @repository)

      refute RepositoryDependencyUpdate.visible.exists?(dry_run_update.id)
    end
  end

  context "::for" do
    test "includes all updates for the same package" do
      rails_updates = RepositoryDependencyUpdate.for(path: "Gemfile.lock", package: "rails")
      assert_same_elements [@requested_update, @completed_update, @errored_update], rails_updates
    end

    test "excludes different dependencies properly" do
      npm_pr = create(:pull_request, repository: @repository, head_ref: "topic-rebased-on-master")
      node_update = create(:repository_dependency_update,
                           repository: @repository,
                           state: :complete,
                           pull_request: npm_pr,
                           manifest_path: "package-lock.json",
                           package_name: "node")

      rails_updates = RepositoryDependencyUpdate.for(path: "Gemfile.lock", package: "rails")
      assert_same_elements [@requested_update, @completed_update, @errored_update], rails_updates

      node_updates = RepositoryDependencyUpdate.for(path: "package-lock.json", package: "node")
      assert_same_elements [node_update], node_updates
    end

    test "excludes same package in different manifest" do
      ruby_pr = create(:pull_request, repository: @repository, head_ref: "ahead")
      nested_rails_update = create(:repository_dependency_update,
                            repository: @repository,
                            state: :complete,
                            pull_request: ruby_pr,
                            manifest_path: "nested/Gemfile.lock",
                            package_name: "rails")

      rails_updates = RepositoryDependencyUpdate.for(path: "Gemfile.lock", package: "rails")
      assert_same_elements [@requested_update, @completed_update, @errored_update], rails_updates

      nested_rails_updates = RepositoryDependencyUpdate.for(path: "nested/Gemfile.lock", package: "rails")
      assert_same_elements [nested_rails_update], nested_rails_updates
    end

    test "excludes different package in same manifest" do
      ruby_pr = create(:pull_request, repository: @repository, head_ref: "ahead")
      rack_update = create(:repository_dependency_update,
                           repository: @repository,
                           state: :complete,
                           pull_request: ruby_pr,
                           manifest_path: "Gemfile.lock",
                           package_name: "rack")

      rails_updates = RepositoryDependencyUpdate.for(path: "Gemfile.lock", package: "rails")
      assert_same_elements [@requested_update, @completed_update, @errored_update], rails_updates

      rack_updates = RepositoryDependencyUpdate.for(path: "Gemfile.lock", package: "rack")
      assert_same_elements [rack_update], rack_updates
    end
  end

  context "#package_manager" do
    test "returns 'bundler' for Ruby manifests" do
      assert_equal :bundler, update_for("path/to/Gemfile").package_manager
      assert_equal :bundler, update_for("path/to/Gemfile.lock").package_manager
    end

    test "returns 'npm_and_yarn' for relevant Javascript mainfests" do
      assert_equal :npm_and_yarn, update_for("path/to/package.json").package_manager
      assert_equal :npm_and_yarn, update_for("path/to/package-lock.json").package_manager
      assert_equal :npm_and_yarn, update_for("path/to/yarn.lock").package_manager
    end

    test "returns 'go_modules' for relevant Go mainfests" do
      assert_equal :go_modules, update_for("path/to/go.mod").package_manager
    end

    test "returns 'pip' for python manifests" do
      assert_equal :pip, update_for("path/to/requirements.txt").package_manager
      assert_equal :pip, update_for("path/to/setup.py").package_manager
      assert_equal :pip, update_for("path/to/Pipfile").package_manager
      assert_equal :pip, update_for("path/to/Pipfile.lock").package_manager
    end

    test "returns 'composer' for relevant PHP manifests" do
      assert_equal :composer, update_for("path/to/composer.json").package_manager
      assert_equal :composer, update_for("path/to/composer.lock").package_manager
    end

    test "returns 'maven' for relevant Java manifests" do
      assert_equal :maven, update_for("pom.xml").package_manager
    end

    test "returns 'nuget' for relevant .NET manifests" do
      assert_equal :nuget, update_for("path/to/.nuspec").package_manager
      assert_equal :nuget, update_for("path/to/.csproj").package_manager
      assert_equal :nuget, update_for("path/to/.vbproj").package_manager
      assert_equal :nuget, update_for("path/to/.vcxproj").package_manager
      assert_equal :nuget, update_for("path/to/.fsproj").package_manager
      assert_equal :nuget, update_for("path/to/packages.config").package_manager
    end

    test "returns 'unknown' for anything else." do
      assert_equal :unknown, update_for("path/to/foo").package_manager
      assert_equal :unknown, update_for("path/to/1").package_manager
      assert_equal :unknown, update_for(nil).package_manager
    end
  end

  context "#requested_or_proposed?" do
    test "true for requested updates" do
      assert_predicate @requested_update, :requested_or_proposed?
    end

    test "false for errored updates" do
      refute_predicate @errored_update, :requested_or_proposed?
    end

    test "true for complete updates with an open PR" do
      assert_predicate @completed_update, :requested_or_proposed?
    end

    test "false for complete updates with a closed PR" do
      update = create_completed_update
      update.pull_request.close

      refute_predicate update.pull_request, :open?
      refute_predicate update.pull_request, :merged?

      assert_predicate update, :requested_or_proposed?
    end

    test "true for complete updates with a merged PR" do
      update = create_completed_update
      update.pull_request.merge

      refute_predicate update.pull_request, :open?
      assert_predicate update.pull_request, :merged?

      assert_predicate update, :requested_or_proposed?
    end
  end

  context "#proposed_change_exists?" do
    test "false if there is no associated Pull Request" do
      refute_predicate @requested_update, :proposed_change_exists?
      refute_predicate @errored_update,   :proposed_change_exists?
    end

    test "true if there is an associated Pull Request" do
      assert_predicate @completed_update, :proposed_change_exists?
    end
  end

  context "#proposed_change_ignored?" do
    test "false if there is no associated Pull Request" do
      refute_predicate @requested_update, :proposed_change_ignored?
      refute_predicate @errored_update,   :proposed_change_ignored?
    end

    test "false if there is an associated, open Pull Request" do
      assert_predicate @completed_update.pull_request, :open?
      refute_predicate @completed_update.pull_request, :merged?

      refute_predicate @completed_update, :proposed_change_ignored?
    end

    test "true if there is an associated, closed Pull Request" do
      update = create_completed_update
      update.pull_request.close

      refute_predicate update.pull_request, :open?
      refute_predicate update.pull_request, :merged?

      assert_predicate update, :proposed_change_ignored?
    end

    test "false if there is an associated, merged Pull Request" do
      update = create_completed_update
      update.pull_request.merge

      refute_predicate update.pull_request, :open?
      assert_predicate update.pull_request, :merged?

      refute_predicate update, :proposed_change_ignored?
    end
  end

  context "Repository#dependency_updates" do
    test "returns all updates for a repository" do
      npm_pr = create(:pull_request, repository: @repository, head_ref: "topic-rebased-on-master")
      node_update = create(:repository_dependency_update,
                           repository: @repository,
                           state: :complete,
                           pull_request: npm_pr,
                           manifest_path: "package-lock.json",
                           package_name: "node")

      assert_same_elements [@requested_update, @completed_update, @errored_update, node_update], @repository.dependency_updates
    end
  end

  context "#viable_update?" do
    test "excludes `job_repo_not_found` errors" do
      @errored_update.error_type = "job_repo_not_found"

      refute @errored_update.viable_update?
    end
  end

  context "#dependabot_has_timed_out?" do
    include ActiveSupport::Testing::TimeHelpers

    test "is false for a newly requested job" do
      @update = create(:repository_dependency_update,
                       :requested,
                       repository: @repository,
                       manifest_path: "Gemfile.lock",
                       package_name: "rails")

      refute @update.dependabot_has_timed_out?
    end

    test "is true for a job requested manually 41 minutes ago" do
      @update = travel_to(41.minutes.ago) do
        create(
          :repository_dependency_update,
          :requested,
          trigger_type: :manual,
          repository: @repository,
          manifest_path: "Gemfile.lock",
          package_name: "rails"
        )
      end

      assert @update.dependabot_has_timed_out?
    end

    test "is true for a job requested automatically 24 hours and 1 minute ago" do
      @update = travel_to(1441.minutes.ago) do
        create(
          :repository_dependency_update,
          :requested,
          trigger_type: :scan,
          repository: @repository,
          manifest_path: "Gemfile.lock",
          package_name: "rails"
        )
      end

      assert @update.dependabot_has_timed_out?
    end

    test "is false for a job requested manually 41 minutes ago that is complete" do
      @update = travel_to(41.minutes.ago) do
        create(
          :repository_dependency_update,
          :complete,
          trigger_type: :manual,
          repository: @repository,
          pull_request: @pull_request,
          manifest_path: "Gemfile.lock",
          package_name: "rails"
        )
      end

      refute @update.dependabot_has_timed_out?
    end

    test "is false for a job requested automatically 24 hours and 1 minute ago that is complete" do
      @update = travel_to(1441.minutes.ago) do
        create(
          :repository_dependency_update,
          :complete,
          trigger_type: :scan,
          repository: @repository,
          pull_request: @pull_request,
          manifest_path: "Gemfile.lock",
          package_name: "rails"
        )
      end

      refute @update.dependabot_has_timed_out?
    end

    test "is false for a job requested manually 41 minutes ago that has errored" do
      @update = travel_to(41.minutes.ago) do
        create(
          :repository_dependency_update,
          :errored,
          trigger_type: :manual,
          repository: @repository,
          manifest_path: "Gemfile.lock",
          package_name: "rails"
        )
      end

      refute @update.dependabot_has_timed_out?
    end

    test "is false for a job requested automatically 24 hours and 1 minute ago that has errored" do
      @update = travel_to(1441.minutes.ago) do
        create(
          :repository_dependency_update,
          :errored,
          trigger_type: :scan,
          repository: @repository,
          manifest_path: "Gemfile.lock",
          package_name: "rails"
        )
      end

      refute @update.dependabot_has_timed_out?
    end
  end

  context "::request_for_repository" do
    test "it creates an update if an alert exists" do
      alert = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability,
        vulnerable_version_range: @rails_vulnerable_version,
      )

      updates = RepositoryDependencyUpdate.request_for_repository(@repository, trigger: :install)

      assert_equal 1, updates.length

      update = updates.first
      assert_predicate update, :valid?
      assert_equal alert, update.repository_vulnerability_alert
    end

    test "it does nothing if no alerts exist" do
      updates = RepositoryDependencyUpdate.request_for_repository(@repository, trigger: :install)

      assert_empty updates
    end

    test "it does nothing if Dependabot is paused" do
      Repository::DependabotServiceManager.new(@repository).pause

      alert = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability,
        vulnerable_version_range: @rails_vulnerable_version,
      )

      updates = RepositoryDependencyUpdate.request_for_repository(@repository, trigger: :install)

      assert_empty updates
    end
  end

  context "::request_for_dependency" do
    test "it creates an update if an alert exists" do
      alert = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability,
        vulnerable_version_range: @rails_vulnerable_version,
      )

      update = RepositoryDependencyUpdate.request_for_dependency(repository: @repository,
                                                                 manifest_path: "Gemfile.lock",
                                                                 package_name: "rails",
                                                                 trigger: :install)

      assert update
      assert_predicate update, :valid?
      assert_equal alert, update.repository_vulnerability_alert
    end

    test "it does nothing if no alerts exist" do
      update = RepositoryDependencyUpdate.request_for_dependency(repository: @repository,
                                                                 manifest_path: "Gemfile.lock",
                                                                 package_name: "rails",
                                                                 trigger: :install)

      refute update
    end

    test "it does nothing if Dependabot is paused" do
      Repository::DependabotServiceManager.new(@repository).pause

      alert = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability,
        vulnerable_version_range: @rails_vulnerable_version,
      )

      update = RepositoryDependencyUpdate.request_for_dependency(repository: @repository,
                                                                 manifest_path: "Gemfile.lock",
                                                                 package_name: "rails",
                                                                 trigger: :install)

      refute update
    end

    test "it still creates manually requested updated even if Dependabot is paused" do
      Repository::DependabotServiceManager.new(@repository).pause

      alert = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability,
        vulnerable_version_range: @rails_vulnerable_version,
      )

      update = RepositoryDependencyUpdate.request_for_dependency(repository: @repository,
                                                                 manifest_path: "Gemfile.lock",
                                                                 package_name: "rails",
                                                                 trigger: :manual)

      assert update
      assert_predicate update, :valid?
      assert_equal alert, update.repository_vulnerability_alert
    end
  end

  context "::manifest_path_supported?" do
    # Covers supported manifest file types that would be detected by Dependency Graph:
    test "returns true for a supported static manifest path" do
      %w(Gemfile.lock another/path/to/a/Gemfile.lock package-lock.json).each do |path|
        assert RepositoryDependencyUpdate.manifest_path_supported?(path), "Expected #{path} to be supported"
      end
    end

    # Covers supported manifest file types that can only be submitted through Dependency Submission API:
    test "returns true for manifest paths explicitly allowed, but not detected by Dependency Graph" do
      %w(
        build.gradle another/path/to/a/build.gradle
        build.gradle.kts another/path/to/a/build.gradle.kts
        settings.gradle another/path/to/a/settings.gradle
        settings.gradle.kts another/path/to/a/settings.gradle.kts
      ).each do |path|
        assert RepositoryDependencyUpdate.manifest_path_supported?(path), "Expected #{path} to be supported"
      end
    end

    # Protects us from creating RepositoryDependencyUpdate records for unsupported
    # manifest types that might be submitted via Dependency Submission API:
    test "returns false for unknown paths input via Dependency Submission API" do
      %w(build.sbt manifest-type-that-doesnt-exist-yet.lol).each do |path|
        refute RepositoryDependencyUpdate.manifest_path_supported?(path), "Expected #{path} to be unsupported"
      end
    end
  end
end
