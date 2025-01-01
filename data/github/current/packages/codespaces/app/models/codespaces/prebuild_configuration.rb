# typed: true
# frozen_string_literal: true

module Codespaces
  class PrebuildConfiguration < ApplicationRecord::Domain::Codespaces
    self.table_name = "codespace_prebuild_configurations"

    include Instrumentation::Model
    include Codespaces::VscsTargetDependency

    enum :trigger, {
      push: 1,
      configuration: 2,
      schedule: 3
    }, suffix: true

    enum :state, {
      enabled: 0,
      disabled: 1,
    }

    DEFAULT_FAST_PATH_ENABLED = true
    DEFAULT_TRIGGER = :push
    DEFAULT_STATE = :enabled
    DEFAULT_MAX_VERSIONS = 2
    DEFAULT_VSCS_TARGET = Codespaces::Vscs.default_target.to_s
    INSTRUMENT_CREATE = :create
    INSTRUMENT_UPDATE = :update
    INSTRUMENT_DESTROY = :destroy
    INSTRUMENT_RUN_TRIGGERED = :run_triggered
    INSTRUMENT_EVENT_TYPES = [INSTRUMENT_CREATE, INSTRUMENT_UPDATE, INSTRUMENT_DESTROY, INSTRUMENT_RUN_TRIGGERED]

    # rubocop:todo Rails/InverseOf
    has_many :locations,
      foreign_key: "codespace_prebuild_configuration_id",
      class_name: "Codespaces::PrebuildConfigurationLocation",
      dependent: :destroy
    # rubocop:enable Rails/InverseOf

    # rubocop:todo Rails/InverseOf
    has_many :schedules,
      foreign_key: "codespace_prebuild_configuration_id",
      class_name: "Codespaces::PrebuildTemplateCreationSchedule",
      dependent: :destroy
    # rubocop:enable Rails/InverseOf

    has_many :prebuild_templates,
    class_name: "Codespaces::PrebuildTemplate",
    inverse_of: :configuration

    # rubocop:todo Rails/InverseOf
    has_many :actors_to_notify,
      foreign_key: "codespace_prebuild_configuration_id",
      class_name: "Codespaces::PrebuildNotificationActor",
      dependent: :destroy
    # rubocop:enable Rails/InverseOf

    # rubocop:todo Rails/InverseOf
    has_many :allowed_permissions,
      foreign_key: "codespace_prebuild_configuration_id",
      class_name: "Codespaces::AllowedPermission",
      dependent: :destroy
    # rubocop:enable Rails/InverseOf

    include ::Repositories::BelongsToRepository
    belongs_to_repository_via_domain legacy_return_type: true
    # rubocop:todo Rails/InverseOf
    belongs_to :latest_workflow_run, -> (configuration) { where(repository_id: configuration.repository_id) }, foreign_key: "latest_workflow_run_id", class_name: "Actions::WorkflowRun"
    # rubocop:enable Rails/InverseOf

    before_validation :ensure_default_state, :ensure_default_devcontainer_path, :ensure_default_vscs_target

    validates :repository, :branch, :trigger, presence: true
    validates :trigger, inclusion: { in: triggers, message: "%{value} is not a valid trigger" }

    validates :repository, uniqueness: {
      scope: [:branch, :vscs_target, :devcontainer_path], message: ->(object, _) do
        error_message = "and branch '#{object.branch}'"
        error_message += " and configuration file '#{object.devcontainer_path}'" if object.devcontainer_path.present?
        error_message += " already belong to a configuration"
        error_message += " on #{object.vscs_target}" unless object.vscs_target == :production
        error_message
      end
    }

    validate :valid_branch, :valid_schedules, :valid_maximum_template_versions

    validates :locations, length: { minimum: 1, message: "You must select at least one region" }

    validate :valid_local_target_url, if: -> { T.bind(self, PrebuildConfiguration); vscs_target&.to_sym == :local }

    delegate :owner, to: :repository

    before_save :ensure_default_trigger, :ensure_default_max_versions

    def targeted_geos
      locations.map { |location| Codespaces::Locations::Geo.find(location.geo) }.compact.uniq
    end

    def targets_all_geos?
      targeted_geos.length == Codespaces::Locations::Geo.public.length
    end

    def build_initial_locations(all: false, locations: [])
      geos = all ? Codespaces::Locations::Geo.where(vscs_target:).map(&:id) : locations
      build_initial_geos(geos_to_set: geos)
    end

    def update_locations(all: false, locations: [])
      geos = all ? Codespaces::Locations::Geo.where(vscs_target:).map(&:id) : locations
      update_geos(new_geos: geos)
    end

    # create day, time, and time zone info into delivery time attribute
    def build_delivery_times(delivery_days: [], delivery_times: [], time_zone_name:)

      days = Array(delivery_days).uniq.select(&:present?)
      times = Array(delivery_times).uniq.select(&:present?)

      schedules = days.product(times).map do |(day, time)|
        { delivery_day: day, delivery_time: time, time_zone_name: time_zone_name }
      end

      self.schedules.build(schedules)
    end

    def update_delivery_times(new_trigger:, delivery_days: [], delivery_times: [], time_zone_name:)

      self.schedules.destroy_all
      if new_trigger != :schedule.to_s
        return
      end

      build_delivery_times(delivery_days: delivery_days, delivery_times: delivery_times, time_zone_name: time_zone_name)

    end

    def latest_workflow_run_for_display
      return latest_workflow_run unless FeatureFlag.vexi.enabled_or_raise?(:codespaces_prebuild_non_pending_status, repository) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      return latest_workflow_run unless latest_workflow_run&.pending?

      check_suite_ids = workflow&.workflow_runs.where(head_branch: branch).pluck(:check_suite_id)

      latest_non_pending_run = CheckSuite.where(id: check_suite_ids, repository_id: repository_id).not_pending.most_recent.first&.workflow_run

      latest_non_pending_run || latest_workflow_run
    end

    def has_ran?
      latest_workflow_run.present?
    end

    def ref_for_display
      Git::Ref.value_for_display(branch)
    end

    def region_names
      Codespaces::VscsServiceStamp.where(vscs_target:, geo: self.locations.pluck(:geo).uniq, prebuild_templates_allowed: true).map { |stamp| stamp.region.id }.sort
    end

    def locations_stored
      self.locations.pluck(:geo).uniq.sort
    end

    def schedule_days
      return @schedule_days if @schedule_days.present?
      self.schedules.pluck(:delivery_day)
    end

    def schedule_times
      return @schedule_times if @schedule_times.present?
      self.schedules.pluck(:delivery_time).sort
    end

    def schedule_time_zone_name
      return @schedule_time_zone_name if @schedule_time_zone_name.present?
      self.schedules.pluck(:time_zone_name).first
    end

    def users_to_notify
      user_ids = self.actors_to_notify.where(owner_type: :User).pluck(:owner_id)
      return [] if user_ids.empty?

      User.where(id: user_ids)
    end

    def teams_to_notify
      team_ids = self.actors_to_notify.where(owner_type: :Team).pluck(:owner_id)
      return [] if team_ids.empty?

      Team.where(id: team_ids)
    end

    def build_actors_to_notify(user_logins: [], team_slugs: [])
      User.where(login: user_logins).pluck(:id).each do |id|
        self.actors_to_notify.build(owner_id: id, owner_type: :User)
      end

      Team.where(slug: team_slugs, organization: repository&.organization).pluck(:id).each do |id|
        self.actors_to_notify.build(owner_id: id, owner_type: :Team)
      end
    end

    def update_actors_to_notify(user_logins: [], team_slugs: [])
      self.actors_to_notify.destroy_all

      build_actors_to_notify(user_logins: user_logins, team_slugs: team_slugs)
    end

    def instrument_event(type:, user:)
      raise ArgumentError, "Invalid audit log event type: #{type}" unless INSTRUMENT_EVENT_TYPES.include?(type)
      instrument(
        type,
        {
          user: user,
          prefix: "prebuild_configuration"
        }
      )
    end

    def event_payload
      payload = {
        branch: branch,
        repository: repository,
        vscs_target: vscs_target,
        locations: region_names,
        trigger: trigger
      }

      payload[owner.event_prefix] = owner if owner

      payload
    end

    # We handle deleting templates in the service here because the service cleans up all templates
    # that pertain to a configuration's attributes, not each template individually.
    def destroy_with_template_clean_up
      # Clean up prebuild templates associated with this prebuild configuration
      Codespaces::DeletePrebuildTemplatesJob.perform_later(
        branch: branch,
        locations: region_names,
        repository_id: repository_id,
        vscs_target: vscs_target,
        vscs_target_url: vscs_target_url,
        devcontainer_path: devcontainer_path,
        configuration_id: self.id
      )

      self.destroy
    end

    # Destroys all prebuild configurations & templates that match the branch and repository across all vscs targets and locations.
    def self.destroy_prebuilds(branch:, repository:)
      configurations = PrebuildConfiguration.where(repository: repository, branch: branch).includes(:locations)
      return if configurations.empty?
      configurations.each(&:destroy_with_template_clean_up)
    end

    def trigger_prebuild_template_creation(commit_sha: nil, previous_sha: nil)
      return if self.disabled?

      if commit_sha.nil?
        commit_sha = latest_commit_sha
      end

      Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_later(
        repository: repository,
        branch: branch,
        locations: region_names,
        commit_sha: commit_sha,
        concurrency_modifier: id.to_s,
        vscs_target: vscs_target,
        vscs_target_url: vscs_target_url,
        devcontainer_path: devcontainer_path,
        configuration: self,
        previous_sha: previous_sha,
      )
    end

    def trigger_update_prebuild_template_version
      region_names.each do |region|
        Codespaces::UpdatePrebuildTemplateVersionsJob.perform_later(
          prebuild_configuration_id: id,
          repository: repository,
          location: region,
          vscs_target: vscs_target,
        )
      end
    end

    def disable
      self.state = :disabled
    end

    def toggle_state
      if self.disabled?
        self.state = :enabled
      else
        self.state = :disabled
      end
    end

    private

    def build_initial_geos(geos_to_set:)
      geos_hash = geos_to_set.map { |geo| { geo: geo, location: Codespaces::Locations::Geo.find(geo).primary_region.id } }
      self.locations.build(geos_hash)
    end

    def update_geos(new_geos:)
      existing_geos = self.locations.pluck(:geo)

      geos_to_add = new_geos - existing_geos
      geos_to_add_hash = geos_to_add.map { |geo| { geo: geo, location: Codespaces::Locations::Geo.find(geo).primary_region.id } }
      self.locations.create(geos_to_add_hash)

      geos_to_remove = existing_geos - new_geos
      self.locations.where(geo: geos_to_remove).destroy_all
    end

    def valid_branch
      # Added this here because when a branch is empty it was returning two validation errors in the messaging:
      # "Branch must be present AND Branch '' does not exist on the repository"
      return unless branch.present?
      errors.add(:branch, message: "'#{branch}' does not exist on the repository") unless repository&.branch_exists?(branch)
    end

    def valid_schedules
      # Validate when the trigger is set to :schedule, we have valid items in schedules list
      return unless trigger.to_sym == :schedule
      if schedules.empty?
        errors.add(:trigger, message: "'Scheduled' is not a valid trigger without selecting a day, time, and time zone")
      end
    end

    def valid_maximum_template_versions
      # Added this here because we should keep at least one template version for each prebuild configuration
      return unless maximum_template_versions.present? && maximum_template_versions < 1
      errors.add(:maximum_template_versions, message: "Template version count cannot be smaller than 1.")
    end

    def workflow
      workflow = Actions::Workflow.find_by(repository: repository, path: Codespaces::Prebuilds.workflow_path(vscs_target), imposer_repository_id: 0)
    end

    def ensure_default_trigger
      return if self.trigger.present?
      self.trigger = Codespaces::PrebuildConfiguration::DEFAULT_TRIGGER
    end

    def ensure_default_devcontainer_path
      return if self.devcontainer_path.present?

      branch_ref = repository&.refs&.find(self.branch)
      self.devcontainer_path = Codespaces::DevContainer.get_default_path(repository, branch_ref&.target_oid)
    end

    def ensure_default_state
      return if self.state.present?
      self.state = Codespaces::PrebuildConfiguration::DEFAULT_STATE
    end

    def ensure_default_max_versions
      return if self.maximum_template_versions.present?
      self.maximum_template_versions = Codespaces::PrebuildConfiguration::DEFAULT_MAX_VERSIONS
    end

    def ensure_default_permission
      return if self.permission_granted.present?
      self.permission_granted = true
    end

    def ensure_default_vscs_target
      # when vscs_target is nil it is read as the default value, so we want to ensure it is always set in the database
      return unless self.vscs_target.nil? || self.vscs_target&.to_sym == Codespaces::Vscs.default_target
      self.vscs_target = Codespaces::PrebuildConfiguration::DEFAULT_VSCS_TARGET
    end

    def valid_local_target_url
      unless Codespaces::Vscs.valid_local_target_url?(repository: repository, vscs_target: vscs_target, vscs_target_url: vscs_target_url)
        errors.add(:vscs_target_url, "must be a valid local target URL")
      end
    end

    def latest_commit_sha
      commit_sha = repository&.ref_to_sha(self.branch)

      commit_sha
    end
  end
end
