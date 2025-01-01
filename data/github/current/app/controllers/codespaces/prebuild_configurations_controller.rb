# typed: true
# frozen_string_literal: true

module Codespaces
  class PrebuildConfigurationsController < AbstractRepositoryController
    before_action :require_codespace_access
    before_action :require_actions_enabled, except: [:destroy]
    before_action :ensure_admin_access
    before_action :require_prebuild_usage, only: [:run_workflow]
    before_action :require_configuration_access, except: [:new, :create, :add_consented_permissions, :suggested_notifiers]
    before_action :valid_prebuild_access_create_or_update, only: [:create, :update]
    before_action :valid_prebuild_access_destroy, only: [:destroy]

    javascript_bundle "codespaces-prebuild-configurations"
    javascript_bundle "codespaces-branch-selector"

    include BranchesHelper

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Spokes,
      ApplicationRecord::RepositoriesPushes,
      ApplicationRecord::Mysql2,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Iam,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Memex,
      ApplicationRecord::Billing,
      only: [:edit]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Iam,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::RepositoriesActionsChecks,
      ApplicationRecord::Billing,
      only: [:latest_run_status]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::RepositoriesPushes,
      ApplicationRecord::Spokes,
      ApplicationRecord::Mysql2,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Iam,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Memex,
      ApplicationRecord::Billing,
      ApplicationRecord::Ballast,
      only: [:new]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Billing,
      only: [:suggested_notifiers]

    depends_on_clusters ApplicationRecord::Copilot,
      optional: true,
      only: [:new, :edit, :latest_run_status]

    def new
      if billed_to_individual?
        default_region = Codespaces::Locations::Region.find(Codespaces::GetRegionForUser.call(user: current_user, repository: current_repository, vscs_target: :production))
        selected_locations = [default_region.geo.id]
        maximum_template_versions = 1
      else
        selected_locations = Codespaces::Locations::Geo.public.map(&:id)
        maximum_template_versions = 2
      end

      render "codespaces/prebuild_configurations/new", locals: {
        vscs_target_options: Codespaces::Vscs.available_vscs_target_configs(current_user),
        repository: current_repository,
        all_locations_selected: !billed_to_individual?,
        selected_locations:,
        branch_ref_selector_cache_key: branch_ref_selector_cache_key,
        prebuild_usage_message: prebuild_usage_message,
        maximum_template_versions:,
        runner_group_options: runner_group_options,
      }
    end

    def create
      prebuild_configuration = PrebuildConfiguration.new(prebuild_configuration_attributes)

      prebuild_configuration.build_initial_locations(
        all: location_preference_is_all?,
        locations: configuration_params[:locations]&.filter_map(&:presence)
      )

      if prebuild_configuration.trigger == :schedule.to_s
        prebuild_configuration.build_delivery_times(
          delivery_days: configuration_params[:delivery_days],
          delivery_times: configuration_params[:delivery_times],
          time_zone_name: configuration_params[:time_zone_name]
        )
      end

      prebuild_configuration.build_actors_to_notify(
        user_logins: configuration_params[:users_to_notify],
        team_slugs: configuration_params[:teams_to_notify]
      )

      if prebuild_configuration.save
        # queue prebuild dynamic action job
        prebuild_configuration.trigger_prebuild_template_creation

        prebuild_configuration.instrument_event(
          type: Codespaces::PrebuildConfiguration::INSTRUMENT_CREATE,
          user: current_user
        )

        # check to see if devcontainer.json repo permission need to be approved
        devcontainer_path = prebuild_configuration_attributes[:devcontainer_path]
        branch = prebuild_configuration_attributes[:branch]
        ref = current_repository.refs.find(branch)

        devcontainer = create_devcontainer(
          devcontainer_path: devcontainer_path,
          ref: ref,
        )
        error, template_needs_perms, repo_readable_by_user_count = permissions_needed?(devcontainer: devcontainer, id: prebuild_configuration.id)
        if error.present?
          flash[:notice] = "Prebuild configuration created."
          flash[:error] = error
          render "codespaces/prebuild_configurations/new", locals: {
            vscs_target_options: Codespaces::Vscs.available_vscs_target_configs(current_user),
            repository: current_repository,
            all_locations_selected: location_preference_is_all?,
            branch_ref: current_repository.refs.find(prebuild_configuration_attributes[:branch]),
            selected_locations: configuration_params[:locations]&.filter_map(&:presence),
            selected_target_name: prebuild_configuration_attributes[:vscs_target],
            vscs_target_url: prebuild_configuration_attributes[:vscs_target_url],
            branch_ref_selector_cache_key: branch_ref_selector_cache_key,
            trigger: prebuild_configuration_attributes[:trigger],
            delivery_days: configuration_params[:delivery_days],
            delivery_times: configuration_params[:delivery_times],
            time_zone_name: configuration_params[:time_zone_name],
            maximum_template_versions: prebuild_configuration_attributes[:maximum_template_versions],
            devcontainer_path: prebuild_configuration_attributes[:devcontainer_path],
            prebuild_configuration_attributes: prebuild_configuration_attributes[:fast_path_enabled],
            prebuild_usage_message: prebuild_usage_message,
            runner_group_options: runner_group_options,
          }
          return
        end

        if template_needs_perms && repo_readable_by_user_count.present? && repo_readable_by_user_count > 0
          render "codespaces/prebuild_configurations/allow_permissions", locals: {
            ref: ref,
            devcontainer: devcontainer,
            repo_readable_by_user_count: repo_readable_by_user_count,
            devcontainer_path: devcontainer_path,
            is_prebuild: true,
            branch: branch,
            is_creating: true,
          }, formats: :html
        else
          flash[:notice] = "Prebuild configuration created"
          redirect_to codespaces_repository_settings_path
        end

      else
        flash[:error] = error_message(errors: prebuild_configuration.errors)

        render "codespaces/prebuild_configurations/new", locals: {
          vscs_target_options: Codespaces::Vscs.available_vscs_target_configs(current_user),
          repository: current_repository,
          all_locations_selected: location_preference_is_all?,
          branch_ref: current_repository.refs.find(prebuild_configuration_attributes[:branch]),
          selected_locations: configuration_params[:locations]&.filter_map(&:presence),
          selected_target_name: prebuild_configuration_attributes[:vscs_target],
          vscs_target_url: prebuild_configuration_attributes[:vscs_target_url],
          branch_ref_selector_cache_key: branch_ref_selector_cache_key,
          trigger: prebuild_configuration_attributes[:trigger],
          delivery_days: configuration_params[:delivery_days],
          delivery_times: configuration_params[:delivery_times],
          time_zone_name: configuration_params[:time_zone_name],
          maximum_template_versions: prebuild_configuration_attributes[:maximum_template_versions],
          devcontainer_path: prebuild_configuration_attributes[:devcontainer_path],
          fast_path_enabled: prebuild_configuration_attributes[:fast_path_enabled],
          prebuild_usage_message: prebuild_usage_message,
          runner_group_options: runner_group_options,
        }
      end
    end

    def edit
      prebuild_configuration = Codespaces::PrebuildConfiguration.find(params[:id])
      selected_locations = prebuild_configuration.locations_stored
      delivery_days = prebuild_configuration.schedule_days
      delivery_times = prebuild_configuration.schedule_times
      time_zone_name = prebuild_configuration.schedule_time_zone_name
      users_to_notify = prebuild_configuration.users_to_notify
      teams_to_notify = prebuild_configuration.teams_to_notify

      render "codespaces/prebuild_configurations/edit", locals: {
        vscs_target_options: Codespaces::Vscs.available_vscs_target_configs(current_user),
        repository: current_repository,
        prebuild_configuration: prebuild_configuration,
        branch_ref: current_repository.refs.find(prebuild_configuration.branch),
        selected_locations: selected_locations,
        all_locations_selected: prebuild_configuration.targets_all_geos?,
        branch_ref_selector_cache_key: branch_ref_selector_cache_key,
        trigger: prebuild_configuration.trigger,
        delivery_days: delivery_days.uniq,
        delivery_times: delivery_times.uniq,
        time_zone_name: time_zone_name,
        users_to_notify: users_to_notify,
        teams_to_notify: teams_to_notify,
        maximum_template_versions: prebuild_configuration.maximum_template_versions,
        devcontainer_path: prebuild_configuration.devcontainer_path,
        fast_path_enabled: prebuild_configuration.fast_path_enabled,
        prebuild_usage_message: prebuild_usage_message,
        runner_group_options: runner_group_options,
      }
    end

    def update
      prebuild_configuration = PrebuildConfiguration.find(params[:id])

      # keep track of locations before update to delete disabled templates
      selected_locations = location_preference_is_all? ? Codespaces::Locations::Geo.where(vscs_target: Codespaces::Vscs.default_target).map(&:id) : configuration_params[:locations]&.filter_map(&:presence)
      existing_locations = prebuild_configuration.locations_stored
      old_maximum_template_versions = prebuild_configuration.maximum_template_versions

      prebuild_configuration.transaction do
        prebuild_configuration.update_locations(
          all: location_preference_is_all?,
          locations: configuration_params[:locations]&.filter_map(&:presence)
        )
        prebuild_configuration.update_delivery_times(
          new_trigger: configuration_params[:trigger],
          delivery_days: configuration_params[:delivery_days],
          delivery_times: configuration_params[:delivery_times],
          time_zone_name: configuration_params[:time_zone_name]
        )

        prebuild_configuration.update_actors_to_notify(user_logins: configuration_params[:users_to_notify], team_slugs: configuration_params[:teams_to_notify])

        unless prebuild_configuration.update(prebuild_configuration_attributes)
          raise ActiveRecord::Rollback
        end
      end

      if prebuild_configuration.errors.any?
        flash[:error] = error_message(errors: prebuild_configuration.errors)
        redirect_to :back
      else
        # queue prebuild dynamic action job
        prebuild_configuration.trigger_prebuild_template_creation
        if old_maximum_template_versions != prebuild_configuration_attributes[:maximum_template_versions].to_i
          prebuild_configuration.trigger_update_prebuild_template_version
        end
        # clean up templates from disabled target/branch/region
        cleanup_disabled_templates(
         selected_locations: selected_locations,
         existing_locations: existing_locations,
         prebuild_configuration: prebuild_configuration
        )

        prebuild_configuration.instrument_event(
          type: Codespaces::PrebuildConfiguration::INSTRUMENT_UPDATE,
          user: current_user
        )

        # check to see if devcontainer.json repo permission need to be approved
        devcontainer_path = prebuild_configuration_attributes[:devcontainer_path]
        branch = prebuild_configuration_attributes[:branch]
        ref = current_repository.refs.find(branch)

        devcontainer = create_devcontainer(
          devcontainer_path: devcontainer_path,
          ref: ref)

        error, template_needs_perms, repo_readable_by_user_count = permissions_needed?(devcontainer: devcontainer, id: prebuild_configuration.id)
        if error.present?
          flash[:notice] = "Prebuild configuration updated"
          flash[:error] = error
          redirect_to codespaces_repository_settings_path
          return
        end

        if template_needs_perms && repo_readable_by_user_count.present? && repo_readable_by_user_count > 0
          render "codespaces/prebuild_configurations/allow_permissions", locals: {
            ref: ref,
            devcontainer: devcontainer,
            repo_readable_by_user_count: repo_readable_by_user_count,
            devcontainer_path: devcontainer_path,
            is_prebuild: true,
            branch: branch,
            is_creating: false,
          }, formats: :html
        else
          flash[:notice] = "Prebuild configuration updated"
          redirect_to codespaces_repository_settings_path
        end
      end
    end

    def create_devcontainer(devcontainer_path:, ref:) # rubocop:todo GitHub/UseRestfulActions
      oid = ref&.target_oid
      Codespaces::DevContainer.new(
        repository: current_repository,
        oid: oid,
        filepath: devcontainer_path,
        user: current_user,
        is_prebuild: true,
      )
    end

    def destroy
      prebuild_configuration = PrebuildConfiguration.find(params[:id])

      prebuild_configuration.instrument_event(
        type: Codespaces::PrebuildConfiguration::INSTRUMENT_DESTROY,
        user: current_user
      )
      prebuild_configuration.destroy_with_template_clean_up

      flash[:notice] = "Prebuild configuration deleted"
      redirect_to codespaces_repository_settings_path
    end

    def run_workflow # rubocop:todo GitHub/UseRestfulActions
      begin
        prebuild_configuration = Codespaces::PrebuildConfiguration.find(params[:id])
        branch = prebuild_configuration.branch

        # queue prebuild dynamic action job
        prebuild_configuration.trigger_prebuild_template_creation

        prebuild_configuration.instrument_event(
            type: Codespaces::PrebuildConfiguration::INSTRUMENT_RUN_TRIGGERED,
            user: current_user
          )

        flash[:notice] = "Prebuild workflow run triggered"
      rescue ActiveRecord::RecordNotFound
        # If the branch gets deleted in the background and deletes related prebuild configurations
        flash[:error] = "Prebuild workflow run failed: prebuild configuration no longer exists"
      end

      redirect_to codespaces_repository_settings_path
    end

    def toggle_state # rubocop:todo GitHub/UseRestfulActions
      prebuild_configuration = Codespaces::PrebuildConfiguration.find(params[:id])
      prebuild_configuration.toggle_state

      unless prebuild_configuration.save
        flash[:error] = "Failed to #{prebuild_configuration.disabled? ? 'enable' : 'disable'} prebuild configuration. Please try again."
        return redirect_to codespaces_repository_settings_path
      end

      # if config is re-enabled then trigger dynamic workflow run to update template
      if prebuild_configuration.enabled?
        # queue prebuild dynamic action job
        prebuild_configuration.trigger_prebuild_template_creation

        # if config runs on a schedule, then calculate next schedule delivery time
        if prebuild_configuration.schedule_trigger?
          prebuild_configuration.schedules.each do |schedule|
            schedule.update_next_delivery_at
          end
        end
      end

      redirect_to codespaces_repository_settings_path
    end

    def suggested_notifiers # rubocop:todo GitHub/UseRestfulActions
      headers["Cache-Control"] = "no-cache, no-store"

      if current_repository.organization.present?
        autocomplete_query = AutocompleteQuery.new(
          current_user,
          params[:q],
          organization: current_repository.organization,
          org_members_only: true,
          include_teams: true
        )
        suggestions = autocomplete_query.suggestions
      elsif current_repository.owner.is_a?(User)
        # if organization is not present then repo owner is the only search option
        suggestions = [current_repository.owner]
      else
        suggestions = []
      end

      respond_to do |format|
        format.html_fragment do
          render partial: "codespaces/prebuild_configurations/notify_suggestions", formats: :html, locals: { suggestions: suggestions }
        end
        format.html do
          render partial: "codespaces/prebuild_configurations/notify_suggestions", locals: { suggestions: suggestions }
        end
      end
    end

    def update_notifiers # rubocop:todo GitHub/UseRestfulActions
      user_names = configuration_params[:users_to_notify]
      users = User.where(login: user_names)

      team_names = configuration_params[:teams_to_notify]
      teams = Team.where(slug: team_names, organization: current_repository.organization)

      respond_to do |format|
        format.html_fragment do
          render Codespaces::PrebuildConfigurations::NotifyOptionsComponent.new(
            repo: current_repository,
            users_to_notify: users,
            teams_to_notify: teams,
          )
        end
        format.html do
          render Codespaces::PrebuildConfigurations::NotifyOptionsComponent.new(
            repo: current_repository,
            users_to_notify: users,
            teams_to_notify: teams,
          )
        end
      end
    end

    def update_config_info # rubocop:todo GitHub/UseRestfulActions
      branch = configuration_params[:branch]

      respond_to do |format|
        format.html_fragment do
          render Codespaces::PrebuildConfigurations::DevcontainerPathSelectComponent.new(
            repository: current_repository,
            initial_branch_ref: current_repository.refs.find(branch),
            devcontainer_path: nil,
          )
        end
        format.html do
          render Codespaces::PrebuildConfigurations::DevcontainerPathSelectComponent.new(
            repository: current_repository,
            initial_branch_ref: current_repository.refs.find(branch),
            devcontainer_path: nil,
          )
        end
      end
    end

    def permissions_needed?(devcontainer:, id:) # rubocop:todo GitHub/UseRestfulActions
      begin
        raise Codespaces::DevContainer::ReadError.new("Devcontainer could not be parsed, repository permissions were not approved.") unless devcontainer.permissions_valid?

        permissions_diff = devcontainer.diff_all_permissions(prebuild_configuration_id: id)
      rescue Codespaces::DevContainer::ReadError => e
        return [e.message, false, 0]
      end

      if permissions_diff.any_permissions?
        # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
        repo_readable_by_user_count = Repository.where(id: current_user.associated_repository_ids(organization: current_repository.owner, min_action: :read)).size
        # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
      end

      [nil, devcontainer&.permissions_need_allowance?, repo_readable_by_user_count]
    end

    def add_consented_permissions # rubocop:todo GitHub/UseRestfulActions
      devcontainer_path = prebuild_configuration_attributes[:devcontainer_path].presence
      branch = prebuild_configuration_attributes[:branch]
      ref = current_repository.refs.find(branch)
      oid = ref&.target_oid
      error_message = nil
      has_opted_out = params[:commit] == "Deny" ? true : false
      is_creating = params[:is_creating] == "true" ? true : false

      prebuild_configuration = T.must(Codespaces::PrebuildConfiguration.where(repository_id: current_repository.id, branch: branch, devcontainer_path: devcontainer_path).first)
      begin
        Codespaces::WriteAllowedPermissions.call(
          user: current_user,
          repository: current_repository,
          ref: oid,
          opt_out: has_opted_out,
          devcontainer_path: devcontainer_path,
          owner_permissions: params[:owner_permissions],
          repository_permissions: params[:repository_permissions],
          category: "prebuild",
          is_prebuild: true,
          prebuild_configuration_id: prebuild_configuration.id,
        )

      rescue ActiveModel::ValidationError => e
        GitHub.dogstats.increment("prebuild.allow_permissions.error.count", tags: ["category:prebuild", "error_type:#{e.class.name}"])
        error_message = "Could not authorize requested permissions: #{e.model.errors.full_messages.to_sentence}"
      rescue Codespaces::Error => e
        GitHub.dogstats.increment("prebuild.allow_permissions.error.count", tags: ["category:prebuild", "error_type:#{e.class.name}"])
        error_message = e.message
      end

      if GitHub.flipper[:codespaces_prebuilds_show_permissions_granted].enabled?(current_repository)
        dc = create_devcontainer(devcontainer_path: devcontainer_path, ref: ref)
        permission_granted = !has_opted_out && !dc.unknown_repository_permissions.present?
        configuration = PrebuildConfiguration.find(T.must(prebuild_configuration.id))
        configuration.update!(permission_granted: permission_granted)
      end

      if error_message
        flash[:error] = error_message
        redirect_to codespaces_repository_settings_path
      else
        if is_creating
          # creating a new prebuild configuration
          flash[:notice] = "Prebuild configuration created"
          redirect_to codespaces_repository_settings_path
        else
          # updating an existing prebuild configuration
          flash[:notice] = "Prebuild configuration updated"
          redirect_to codespaces_repository_settings_path
        end

      end
    end

    # Returns updated run status that uses Alive to live update
    def latest_run_status # rubocop:todo GitHub/UseRestfulActions
      prebuild_configuration = PrebuildConfiguration.find(params[:id])

      render(
        Codespaces::PrebuildConfigurationRunStatusComponent.new(
          configuration: prebuild_configuration,
          current_repo: current_repository,
          repo_owner: current_repository.owner,
          actions_disabled: current_repository.actions_disabled?
        ), layout: false
      )
    end

    private

    memoize def billed_to_individual?
      billable_owner = Codespaces::RepositoryPolicy.async_with_prefill(current_user, current_repository).sync.billable_owner
      !billable_owner.organization?
    end

    memoize def runner_group_options
      if current_repository.feature_enabled?(:codespaces_prebuild_runner_choice)
        return [] unless current_repository.organization
        runners = Actions::LargerRunner.larger_runners_for(entity: current_repository.organization)
        prebuild_runners = runners.select { |r| r.image&.id == CreatePrebuildTemplateDynamicWorkflow::RUNNER_PREBUILD_IMAGE }
        options = [["", ""]] + prebuild_runners.map do |r|
          group = r.inherited? ? "enterprise/#{r.group_name}" : "org/#{r.group_name}"
          ["#{group}  -  #{r.name}", "#{group}/#{r.name}"]
        end.sort
      else
        []
      end
    end

    def prebuild_configuration_attributes
      params_devcontainer_path = configuration_params[:devcontainer_path]

      args = {
        repository: current_repository,
        branch: configuration_params[:branch],
        vscs_target: configuration_params[:vscs_target] || Codespaces::Vscs.default_target,
        maximum_template_versions: configuration_params[:maximum_template_versions],
        trigger: configuration_params[:trigger] || Codespaces::PrebuildConfiguration::DEFAULT_TRIGGER,
        devcontainer_path: params_devcontainer_path.present? ? params_devcontainer_path : nil,
        fast_path_enabled: configuration_params[:disable_fast_path] == "true" ? false : true,
      }

      if current_repository.feature_enabled?(:codespaces_prebuild_runner_choice)
        parts = configuration_params[:larger_runner].to_s.split("  -  ")
        runner_group = parts[0]
        runner_name = parts[1]

        args[:runner_group] = runner_group
        args[:runner_label] = runner_name
      end

      args[:vscs_target_url] = configuration_params[:vscs_target_url] if configuration_params[:vscs_target] == "local"
      args
    end

    def location_preference_is_all?
      configuration_params[:location_preference] == Codespaces::PrebuildConfigurationLocation::ALL_LOCATIONS
    end

    def configuration_params
      params.require(:codespaces_prebuild_configuration)
        .permit(
          :vscs_target,
          :branch,
          :vscs_target_url,
          :location_preference,
          :trigger,
          :time_zone_name,
          :maximum_template_versions,
          :devcontainer_path,
          :permission_granted,
          :ref,
          :disable_fast_path,
          :larger_runner,
          delivery_days: [],
          delivery_times: [],
          locations: [],
          users_to_notify: [],
          teams_to_notify: [])
        .reverse_merge(locations: [], delivery_days: [], delivery_times: [], users_to_notify: [], teams_to_notify: []) # permit below will remove locations from the hash if it's empty but that causes a nil error later on
    end

    def branch_ref_selector_cache_key
      ref_list_cache_key(repository: current_repository)
    end

    def require_codespace_access
      render_404 unless current_repository&.owner&.codespaces_feature_enabled?
    end

    def require_actions_enabled
      render_404 unless current_repository.actions_enabled?
    end

    def require_prebuild_usage
      return render plain: "Prebuilds are disabled due to billing issues", status: 402 if prebuild_usage_message.present?
    end

    def valid_prebuild_access_create_or_update
      vscs_target = prebuild_configuration_attributes[:vscs_target]
      vscs_target_url = prebuild_configuration_attributes[:vscs_target_url]

      valid_prebuild_access(vscs_target: vscs_target, vscs_target_url: vscs_target_url)
    end

    def valid_prebuild_access_destroy
      prebuild_configuration = PrebuildConfiguration.find(params[:id])
      vscs_target = prebuild_configuration.vscs_target
      vscs_target_url = prebuild_configuration.vscs_target_url

      valid_prebuild_access(vscs_target: vscs_target, vscs_target_url: vscs_target_url)
    end

    def valid_prebuild_access(vscs_target:, vscs_target_url:)
      return unless GitHub.flipper[:codespaces_prebuild_controller_developer_check].enabled?(current_user)

      if vscs_target_url.present? && !GitHub.flipper[:codespaces_developer].enabled?(current_user)
        return render_404
      end

      if vscs_target != Codespaces::Vscs.default_target && !GitHub.flipper[:codespaces_developer].enabled?(current_user)
        return render_404
      end

      begin
        Codespaces::ValidatePrebuildAccess.call(
          repository: current_repository,
          vscs_target: vscs_target,
          vscs_target_url: vscs_target_url)
      rescue Codespaces::ValidatePrebuildAccess::AuthorizationError => e
        render_404
      rescue Codespaces::ValidatePrebuildAccess::CreationCircuitBreaker => e
        render_404
      end
    end

    memoize def prebuild_usage_message
      Codespaces::Prebuilds.prebuild_usage_disallowed_message(current_repository&.owner, current_repository)
    end

    # ensure that the user has access to the repository of the originating prebuild configuration
    def require_configuration_access
      begin
        prebuild_configuration = Codespaces::PrebuildConfiguration.find(params[:id])
        user_has_access_to_repo = prebuild_configuration.repository&.adminable_by?(current_user)
        render_404 unless user_has_access_to_repo
      rescue ActiveRecord::RecordNotFound
        # the routes code block will check if the prebuild configuration exists
      end
    end

    def cleanup_disabled_templates(
      selected_locations:,
      existing_locations:,
      prebuild_configuration:)

      previous_changes = prebuild_configuration.previous_changes
      branch_changed = previous_changes.has_key?(:branch.to_s)

      # if the target switched from nil to production do not consider it a change
      vscs_target_changed = previous_changes.has_key?(:vscs_target.to_s) &&
                            !(previous_changes[:vscs_target.to_s].first.blank? && prebuild_configuration.vscs_target&.to_sym == Codespaces::Vscs.default_target)

      vscs_target_url_changed = previous_changes.has_key?(:vscs_target_url.to_s)
      devcontainer_path_changed = previous_changes.has_key?(:devcontainer_path.to_s)

      branch = branch_changed ? previous_changes[:branch.to_s].first : prebuild_configuration.branch
      vscs_target = vscs_target_changed ? previous_changes[:vscs_target.to_s].first&.to_sym : prebuild_configuration.vscs_target
      vscs_target_url = vscs_target_url_changed ? previous_changes[:vscs_target_url.to_s].first : prebuild_configuration.vscs_target_url
      devcontainer_path = devcontainer_path_changed ? previous_changes[:devcontainer_path.to_s].first : prebuild_configuration.devcontainer_path

      locations_to_remove = if branch_changed || vscs_target_changed || devcontainer_path_changed
        existing_locations
      else
        existing_locations - selected_locations
      end

      locations_to_remove = Codespaces::VscsServiceStamp.where(vscs_target:, geo: locations_to_remove.uniq, prebuild_templates_allowed: true).map { |stamp| stamp.region.id }

      unless locations_to_remove.empty?
        # delete all templates for disabled locations
        Codespaces::DeletePrebuildTemplatesJob.perform_later(
            branch: branch,
            locations: locations_to_remove,
            repository_id: current_repository.id,
            vscs_target: vscs_target,
            vscs_target_url: vscs_target_url,
            devcontainer_path: devcontainer_path,
            configuration_id: prebuild_configuration.id,
        )
      end
    end

    def error_message(errors:)
      message = "There was a problem saving your prebuild configuration:"
      errors.each do |error|
        # The user facing term for locations is 'regions' which is used in the custom error message for locations in PrebuildConfiguration
        # #full_message returns the error message with the attribute name prepended while #message only returns the custom error
        # we don't want to return the locations attribute name so we do this check
        error_message = error.attribute == :locations ? error.message : error.full_message
        message += " #{error_message}"
      end
      message
    end
  end
end
