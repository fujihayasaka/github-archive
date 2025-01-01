# rubocop:disable GitHub/FeatureManagement/NoFlipperFeatureUsage
# typed: true
# frozen_string_literal: true

class Devtools::FeatureFlagsController < DevtoolsController
  include GitHub::Memoizer

  skip_before_action :cap_pagination, unless: :robot?, only: :show

  javascript_bundle "feature-flags"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:add_actor]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:add_github_team]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:autocomplete]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:check_actor]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:history]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:in_memory]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:remove_actor]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:team_autocomplete]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:user_autocomplete]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :new, :edit, :add_github_team, :in_memory, :remove_actor, :add_actor,
      :check_actor],
    optional: true

  # Changes are only instantaneous in the primary datacenter. Other datacenters
  # rely on expiring caches to update their flipper settings.
  TTL_WARNING = "Changes may take up to #{Flipper::Adapters::Memcacheable::TTL} seconds to apply."

  STALE_ETAG_WARNING = "The content you are editing has changed. Please refresh the page and reapply your changes."

  MYSQL_FORWARDER_CACHE_KEY = "flipper_mysql_adapter_forwarder_enabled"

  FEATURES_PER_PAGE = 100
  FEATURES_PAGINATION_LIMIT = 25
  HISTORY_ENTRIES_PER_PAGE = 100
  ACTORS_PER_PAGE = 50
  MAXIMUM_TEAM_SIZE = 50
  MAXIMUM_USERS_ADDED_AT_ONCE = 50
  FEATURE_CHANGED_METRIC = "devtools.feature_flags.feature_changed.count"

  def index
    features = FlipperFeature
      .matches_name_or_description(parsed_query.query)
      .service_name_like(parsed_query.service)
      .updated_between(parsed_query.starts, parsed_query.ends)
      .order(Arel.sql(parsed_query.sort)) # Arel.sql avoids nasty SQL injection given some of the query parsing we had to do
      .paginate(page: current_page, per_page: FEATURES_PAGINATION_LIMIT)

    GitHub::PrefillAssociations.prefill_batch_method(features, :prelude_fully_enabled?)
    GitHub::PrefillAssociations.prefill_batch_method(features, :prelude_staff_shipped?)
    GitHub::PrefillAssociations.prefill_batch_method(features, :prelude_actor_or_percentage?)

    render "devtools/feature_flags/index", locals: {
      features: features,
      q: params[:q],
      services: FlipperFeature.order(:service_name).pluck(:service_name).uniq.compact,
      mysql_flipper_forwarder_enabled: FeatureManagement::Kv.store.get(MYSQL_FORWARDER_CACHE_KEY).value!.nil? == false
    }

  end

  def autocomplete # rubocop:todo GitHub/UseRestfulActions
    features = FlipperFeature.matches_name_or_description(params[:q]).limit(FEATURES_PER_PAGE).order(name: :asc)
    render "devtools/feature_flags/autocomplete", formats: :html, layout: false, locals: { features: features }
  end

  def team_autocomplete # rubocop:todo GitHub/UseRestfulActions
    teams = Organization.find(FlipperFeature::GITHUB_ORG_ID)
      .visible_teams_for(current_user)
      .limit(25)

    unless params[:q].blank?
      teams = teams.where("name LIKE ?", "%#{params[:q]}%")
    end

    render "devtools/feature_flags/team_autocomplete", formats: :html, layout: false, locals: {
      teams: teams,
      query: params[:q],
    }
  end

  def service_autocomplete # rubocop:todo GitHub/UseRestfulActions
    services = GitHub::ServiceCatalog
      .find_services_by_name(name: params[:q])
      .reject { |service| service.name.casecmp?(FlipperFeature::GITHUB_SERVICE_NAME) }

    render "devtools/feature_flags/service_autocomplete", formats: :html, layout: false, locals: {
      services: services,
      query: params[:q],
    }
  end

  def user_autocomplete # rubocop:todo GitHub/UseRestfulActions
    users = User.search(params[:q], with_orgs: true)

    render "devtools/feature_flags/user_autocomplete", formats: :html, layout: false, locals: { users: users }
  end

  def show
    feature_flag = find_feature
    if feature_flag.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    actor_type_filter = params[:actor_type]
    show_big_feature_actors = true
    if feature_flag.big_feature?
      show_big_feature_actors = params[:show_big_feature_actors].nil? ? false : true
    end

    actor_gates = nil

    if !feature_flag.big_feature? || show_big_feature_actors
      actor_gates = feature_flag.flipper_gates
        .actor_gates(actor_type: actor_type_filter)
        .order(:created_at)
        .paginate(page: current_page, per_page: ACTORS_PER_PAGE)
    end

    render "devtools/feature_flags/show", locals: {
      feature_flag: feature_flag,
      actor_gates: actor_gates,
      big_feature_threshold: FlipperFeature::BIG_FEATURE_WARNING_THRESHOLD,
      show_big_feature_actors: show_big_feature_actors,
      selected_filter: actor_type_filter,
      celebrate: flash[:celebrate],
    }
  end

  def history # rubocop:todo GitHub/UseRestfulActions
    feature_flag = find_feature
    feature_name = feature_flag&.name || "unknown"

    phrase = "(data.feature_name:#{feature_name})"

    if params[:history_actor].present?
      query = params[:history_actor].strip
      phrase += " AND (actor:#{query} OR data.subject:#{query})"
    end

    if GitHub.driftwood_ade_queries_enabled?
      phrase = <<~KQL
        webevents
        | where data.feature_name == "#{feature_name}"
        #{params[:history_actor].present? ? "| where actor == '#{params[:history_actor].strip}' or data.subject == '#{params[:history_actor].strip}'" : ""}
      KQL
    end

    entries = Audit::Driftwood::Query.new_stafftools_query(
      phrase: phrase,
      current_user: current_user,
      per_page: HISTORY_ENTRIES_PER_PAGE,
    ).execute

    render partial: "devtools/feature_flags/history", locals: { entries: entries }
  end

  def new
    if GitHub.multi_tenant_enterprise?
      return render(plain: "This action is not allowed on a proxima stamp.", status: :bad_request)
    end

    render "devtools/feature_flags/new", locals: {
      feature: FlipperFeature.new,
    }
  end

  def create
    if GitHub.multi_tenant_enterprise?
      return render(plain: "This action is not allowed on a proxima stamp.", status: :bad_request)
    end

    if feature = FlipperFeature.find_by(name: params[:flipper_feature][:name])
      return redirect_to devtools_feature_flag_path(feature), notice: "'#{feature.name}' already exists"
    end

    feature = FlipperFeature.new(flipper_feature_params)
    if !feature.valid?
      flash.now[:error] = "Error creating the feature"
      render "devtools/feature_flags/new", locals: {
        feature: feature,
      }
      return
    end

    GitHub.flipper.disable(params[:flipper_feature][:name]) # rubocop:disable GitHub/FeatureManagement/NoFeatureFlagManipulation
    feature = T.must(FlipperFeature.find_by(name: params[:flipper_feature][:name]))

    if feature.update(flipper_feature_params)
      redirect_to devtools_feature_flag_path(feature), notice: "'#{feature.name}' has been created"
    else
      flash.now[:error] = "Error creating the feature"
      render "devtools/feature_flags/new", locals: {
        feature: feature,
      }
    end
  end

  def edit
    if GitHub.multi_tenant_enterprise?
      return render(plain: "This action is not allowed on a proxima stamp.", status: :bad_request)
    end

    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    render "devtools/feature_flags/edit", locals: { feature: feature }
  end

  def update
    if GitHub.multi_tenant_enterprise?
      return render(plain: "This action is not allowed on a proxima stamp.", status: :bad_request)
    end

    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    feature.exclusion_rule = nil # Force update to the feature-flag-hub

    if feature.update(flipper_feature_params)

      redirect_to devtools_feature_flag_path(feature), notice: "'#{feature.name}' has been updated"
    else
      flash.now[:error] = "Error updating the feature"
      render "devtools/feature_flags/edit", locals: { feature: feature }
    end
  end

  def destroy
    if GitHub.multi_tenant_enterprise?
      return render(plain: "This action is not allowed on a proxima stamp.", status: :bad_request)
    end

    feature = find_feature
    if feature.nil?
      redirect_to devtools_feature_flags_path
      return
    end

    feature.destroy
    record_metric(FEATURE_CHANGED_METRIC, feature.name, ["action:deleted"])

    redirect_to devtools_feature_flags_path, notice: "'#{params[:id]}' has been deleted and disabled. #{TTL_WARNING}"
  end

  def enable # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    feature.rollout_updated_at = params[:rollout_updated_at]
    feature.instance_variable_set(:@should_compare_etag, params.has_key?(:rollout_updated_at))
    feature.exclusion_rule = nil # Force update to the feature-flag-hub

    gate = {
      feature_name: feature.name,
      change_type: "Enabled",
      change_scope: "everyone",
    }

    feature.enable
    redirect_to devtools_feature_flag_path(feature), flash: {
      notice: "Enabled '#{feature.name}' for everyone. #{TTL_WARNING}",
      celebrate: true
    }

  rescue Flipper::Adapters::Mysql::ConcurrencyError => e
    status = analyze_gate_update(true)
    redirect_to devtools_feature_flag_path(feature), flash: create_gate_flash(gate, status)
  end

  def disable # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    feature.rollout_updated_at = params[:rollout_updated_at]
    feature.instance_variable_set(:@should_compare_etag, params.has_key?(:rollout_updated_at))
    feature.exclusion_rule = nil # Force update to the feature-flag-hub

    gate = {
      feature_name: feature.name,
      change_type: "Disabled",
      change_scope: "everyone",
    }

    feature.disable
    redirect_to devtools_feature_flag_path(feature), flash: {
      notice: "Disabled '#{feature.name}' for everyone. #{TTL_WARNING}",
    }

  rescue Flipper::Adapters::Mysql::ConcurrencyError => e
    status = analyze_gate_update(true)
    redirect_to devtools_feature_flag_path(feature), flash: create_gate_flash(gate, status)
  end

  def synchronize_actors # rubocop:todo GitHub/UseRestfulActions
    return redirect_to devtools_feature_flags_path, flash: { error: "Synchronization start date is required." } if params[:start_date].blank?
    return redirect_to devtools_feature_flags_path, flash: { error: "Invalid synchronization start date specified." } unless param_date(params[:start_date])
    return redirect_to devtools_feature_flags_path, flash: { error: "Synchronization start date cannot be in the future." } if param_date(params[:start_date]) > Date.today
    sync_correlation_id = SecureRandom.uuid
    start_date = param_date(params[:start_date])
    current_user_login = "@#{current_user.display_login}"
    job = LegacyFeatureFlag::SyncFeatureActorsJob.perform_later(start_date, current_user_login, sync_correlation_id)

    GitHub.logger.info("Started Sync Feature Actors Job with start date #{start_date}",
      "code.namespace": "Devtools::FeatureFlagsController",
      "code.function": "synchronize_actors",
      "gh.user.id": current_user.id,
      "gh.job.id": "#{job && job.job_id}",
      "gh.correlation_id": sync_correlation_id,
    )

    message = <<~HEREDOC
      Started Sync Feature Actors Job
      Start Date: #{start_date}
      Job ID: #{job && job.job_id}
      Sync Correlation Id #{sync_correlation_id}
    HEREDOC
    GitHub::Chatterbox.client.say!(current_user_login, message)

    redirect_to devtools_feature_flags_path, flash: { notice: "Synchronization job started." }
  end

  def synchronize_feature_flag_actors # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    sync_correlation_id = SecureRandom.uuid
    current_user_login = "@#{current_user.display_login}"
    job = LegacyFeatureFlag::SyncFeatureActorBatchJob.perform_later(feature, current_user_login, sync_correlation_id)

    GitHub.logger.info("Started Sync Feature Actors Batch Job",
      "code.namespace": "Devtools::FeatureFlagsController",
      "code.function": "synchronize_feature_flag_actors",
      "gh.user.id": current_user.id,
      "gh.job.id": "#{job && job.job_id}",
      "gh.correlation_id": sync_correlation_id,
      "feature_flag.key": feature.name,
    )

    message = <<~HEREDOC
      Started Sync Feature Actors Batch Job
      Job ID: #{job && job.job_id}
      Sync Correlation Id #{sync_correlation_id}
    HEREDOC
    GitHub::Chatterbox.client.say!(current_user_login, message)

    redirect_to devtools_feature_flag_path(feature), flash: { notice: "Synchronization job started." }
  end

  def activate_actor_percentage # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    feature.rollout_updated_at = params[:rollout_updated_at]
    feature.instance_variable_set(:@should_compare_etag, params.has_key?(:rollout_updated_at))
    feature.exclusion_rule = nil # Force update to the feature-flag-hub

    percentage = params[:percentage].nil? ? params[:actor_percentage].to_f : params[:percentage].to_f
    gate = {
      feature_name: feature.name,
      change_type: "Enabled",
      change_scope: "#{percentage}% of actors",
    }

    feature.enable_percentage_of_actors(params[:actor_percentage])
    redirect_to devtools_feature_flag_path(feature), notice: "Enabled '#{feature.name}' for #{params[:actor_percentage].to_f}% of actors. #{TTL_WARNING}"
  rescue Flipper::Adapters::Mysql::ConcurrencyError => e
    status = analyze_gate_update(true)
    redirect_to devtools_feature_flag_path(feature), flash: create_gate_flash(gate, status)
  end

  def activate_random_percentage # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    feature.rollout_updated_at = params[:rollout_updated_at]
    feature.instance_variable_set(:@should_compare_etag, params.has_key?(:rollout_updated_at))
    feature.exclusion_rule = nil # Force update to the feature-flag-hub

    percentage = params[:percentage].nil? ? params[:random_percentage].to_f : params[:percentage].to_f
    gate = {
      feature_name: feature.name,
      change_type: "Enabled",
      change_scope: "#{percentage}% of the time",
    }

    feature.enable_percentage_of_time(params[:random_percentage])
    redirect_to devtools_feature_flag_path(feature), notice: "Enabled '#{feature.name}' #{params[:random_percentage].to_f}% of the time. #{TTL_WARNING}"
  rescue Flipper::Adapters::Mysql::ConcurrencyError => e
    status = analyze_gate_update(true)
    redirect_to devtools_feature_flag_path(feature), flash: create_gate_flash(gate, status)
  end

  def add_actor # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    render "devtools/feature_flags/add_actor", locals: { feature: feature }
  end

  def remove_actor # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    render "devtools/feature_flags/remove_actor", locals: { feature: feature }
  end

  def check_actor # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    render "devtools/feature_flags/check_actor", locals: { feature: feature }
  end

  def add_github_team # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    render "devtools/feature_flags/add_github_team", locals: {
      feature: feature,
      maximum_team_size: MAXIMUM_TEAM_SIZE,
    }
  end

  def activate_github_team # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    if params[:flipper_feature].present? && params[:flipper_feature][:github_org_team_id].present?
      team = Team.find_by!(id: params[:flipper_feature][:github_org_team_id], organization_id: FlipperFeature::GITHUB_ORG_ID)

      if team.members_count > MAXIMUM_TEAM_SIZE
        return redirect_to devtools_feature_flag_add_github_team_path(feature), notice: "For performance reasons we don't allow adding teams with more than #{MAXIMUM_TEAM_SIZE} members."
      end

      team.members.each do |member|
        feature.enable(member)
      end
      record_metric("devtools.feature_flags.actor_changed.count", feature.name)

      redirect_to devtools_feature_flag_path(feature), notice: "'#{feature.name}' has been updated. #{TTL_WARNING}"
    else
      redirect_to devtools_feature_flag_add_github_team_path(feature), notice: "A team must be selected to add it as a gate."
    end
  end

  def in_memory # rubocop:todo GitHub/UseRestfulActions
    set_nav_breadcrumb ContextRegion::BasicCrumb.new(nil,
      label: "In-memory Adapter",
      path: in_memory_devtools_feature_flags_path,
      parent: ContextRegion::Devtools::FeatureFlagsIndexCrumb.new
    )

    render "devtools/feature_flags/in_memory"
  end

  def toggle_in_memory_adapter # rubocop:todo GitHub/UseRestfulActions
    message = if ::Flipper::Adapters::InMemory.adapter_enabled?
      ::Flipper::Adapters::InMemory.disable_adapter!
      "In-Memory adapter was disabled"
    else
      ::Flipper::Adapters::InMemory.enable_adapter!
      "In-Memory adapter was enabled"
    end
    redirect_to in_memory_devtools_feature_flags_path, notice: message
  end

  def activate_actor # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    actors = actors_from_params

    should_compare_etag = params.has_key?(:rollout_updated_at) && actors.found.length == 1
    feature.instance_variable_set(:@should_compare_etag, should_compare_etag)
    feature.rollout_updated_at = params[:rollout_updated_at]
    feature.exclusion_rule = nil # Force update to the feature-flag-hub

    actors.found.each { |actor| feature.enable(actor.object) }
    params[:users] = actors.users_not_found
    params[:repos] = actors.repos_not_found

    if actors.errors.empty?
      redirect_to devtools_feature_flag_path(feature), notice: "'#{feature.name}' has been updated. #{TTL_WARNING}"
    else
      flash[:error] = actors.errors.join(" ")
      render "devtools/feature_flags/add_actor", locals: { feature: feature }
    end
  rescue Flipper::Adapters::Mysql::ConcurrencyError
    flash[:error] = STALE_ETAG_WARNING
    redirect_to devtools_feature_flag_path(feature)
  end

  def deactivate_actor # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    actors = actors_from_params

    should_compare_etag = params.has_key?(:rollout_updated_at) && actors.found.length == 1
    feature.instance_variable_set(:@should_compare_etag, should_compare_etag)
    feature.rollout_updated_at = params[:rollout_updated_at]
    feature.exclusion_rule = nil # Force update to the feature-flag-hub

    actors.found.each { |actor| feature.disable(actor.object) }
    params[:users] = actors.users_not_found
    params[:repos] = actors.repos_not_found
    if actors.errors.empty?
      redirect_to devtools_feature_flag_path(feature), notice: "'#{feature.name}' has been updated. #{TTL_WARNING}"
    else
      flash[:error] = actors.errors.join(" ")
      render "devtools/feature_flags/remove_actor", locals: { feature: feature }
    end
  rescue Flipper::Adapters::Mysql::ConcurrencyError
    flash[:error] = STALE_ETAG_WARNING
    redirect_to devtools_feature_flag_path(feature)
  end

  def verify_actor # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    actors = actors_from_params

    if actors.errors.empty?
      actor_statuses = actors.found.map do |actor|
        if FlipperGate.where(flipper_feature_id: feature.id, name: "actors", value: actor.vexi_id).exists? # rubocop:disable GitHub/FeatureManagement/NoFlipperGateUsage
          "#{actor.name} is added to this flag."
        else
          "#{actor.name} is not added to this flag."
        end
      end
      flash[:notice] = actor_statuses.join(" ")
    else
      flash[:error] = actors.errors.join(" ")
    end

    render "devtools/feature_flags/check_actor", locals: { feature: feature }
  end

  def activate_group # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    feature.rollout_updated_at = params[:rollout_updated_at]
    feature.instance_variable_set(:@should_compare_etag, params.has_key?(:rollout_updated_at))
    feature.exclusion_rule = nil # Force update to the feature-flag-hub

    feature.enable_group(params[:group])
    redirect_to devtools_feature_flag_path(feature), \
      notice: "Enabled '#{feature.name}' for the '#{params[:group]}' group. #{TTL_WARNING}"
  rescue Flipper::Adapters::Mysql::ConcurrencyError => e
    flash[:error] = STALE_ETAG_WARNING
    redirect_to devtools_feature_flag_path(feature)
  end

  def deactivate_group # rubocop:todo GitHub/UseRestfulActions
    feature = find_feature
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    feature.rollout_updated_at = params[:rollout_updated_at]
    feature.instance_variable_set(:@should_compare_etag, params.has_key?(:rollout_updated_at))
    feature.exclusion_rule = nil # Force update to the feature-flag-hub

    feature.disable_group(params[:group])
    redirect_to devtools_feature_flag_path(feature), \
      notice: "Removed the '#{params[:group]}' group from '#{feature.name}'. #{TTL_WARNING}"
  rescue Flipper::Adapters::Mysql::ConcurrencyError => e
    flash[:error] = STALE_ETAG_WARNING
    redirect_to devtools_feature_flag_path(feature)
  end

  def toggle_mysql_flipper_forwarder_enabled # rubocop:todo GitHub/UseRestfulActions
    if FeatureManagement::Kv.store.get(MYSQL_FORWARDER_CACHE_KEY).value!.nil?
      FeatureManagement::Kv.store.set(MYSQL_FORWARDER_CACHE_KEY, "true")
    else
      FeatureManagement::Kv.store.del(MYSQL_FORWARDER_CACHE_KEY)
    end

    redirect_to devtools_feature_flags_path
  end

  private

  def set_default_nav_breadcrumb
    return unless header_redesign_enabled?

    feature = find_feature

    if feature
      set_nav_breadcrumb ContextRegion::Devtools::FeatureFlagCrumb.new(feature)
    else
      set_nav_breadcrumb ContextRegion::Devtools::FeatureFlagsIndexCrumb.new
    end
  end

  memoize def parsed_query
    FeatureFlag::Query.new(query: params[:q], current_user: current_user)
  end

  class Actor < T::Struct
    const :name, String
    const :object, Vexi::Actor

    delegate :vexi_id, to: :object
  end

  class ActorsFromParams < T::Struct
    const :found, T::Array[Actor]
    const :users_not_found, T::Array[String]
    const :repos_not_found, T::Array[String]
    const :errors, T::Array[String]
  end

  sig { returns(ActorsFromParams) }
  def actors_from_params
    actors = T.let([], T::Array[Actor])
    users_not_found = []
    repos_not_found = []
    errors = []

    if params[:enterprise].present?
      if business = Business.find_by(slug: params[:enterprise].strip)
        actors << Actor.new(
          object: business,
          name: params[:enterprise],
        )
      else
        errors << "Enterprise #{params[:enterprise]} not found."
      end
    end

    params[:users] = params[:users]&.filter(&:present?)
    if params[:users].present?
      user_names = params[:users]
      if user_names.size > MAXIMUM_USERS_ADDED_AT_ONCE
        users_not_found += user_names
        errors << "The maximum number of users allowed to be added or removed at once is #{MAXIMUM_USERS_ADDED_AT_ONCE}"
      else
        # Get User active records then using index_by to turn the list into a hash where the key is the User's name.
        # Using hash#slice returns a hash containing the removed key/value pairs in the same order as the slice's parameters.
        users = User.with_logins(user_names).index_by { |user| "#{user.name.downcase}" }

        user_names.each do |name|
          if users.has_key?(name.downcase)
            actors << Actor.new(object: users[name], name:)
          else
            users_not_found << name
          end
        end

        if users_not_found.present?
          errors << "#{"User".pluralize(users_not_found.size)} #{users_not_found.to_sentence} not found."
        end
      end
    end

    params[:repos] = params[:repos]&.filter(&:present?)
    if params[:repos].present?
      repo_names_with_owners = params[:repos]
      if repo_names_with_owners.size > MAXIMUM_USERS_ADDED_AT_ONCE
        repos_not_found += repo_names_with_owners
        errors << "The maximum number of repos allowed to be added or removed at once is #{MAXIMUM_USERS_ADDED_AT_ONCE}"
      else
        repos = Repository.with_names_with_owners(repo_names_with_owners).index_by { |repo| repo.nwo.downcase }

        repo_names_with_owners.each do |nwo|
          if repos.has_key?(nwo.downcase)
            actors << Actor.new(object: repos[nwo], name: nwo)
          else
            repos_not_found << nwo
          end
        end

        if repos_not_found.present?
          errors << "#{"Repository".pluralize(repos_not_found.size)} #{repos_not_found.to_sentence} not found."
        end
      end
    end

    if params[:oauth_application].present?
      if oauth_application = OauthApplication.find_by(key: params[:oauth_application].strip)
        actors << Actor.new(object: oauth_application, name: params[:oauth_application])
      else
        errors << "OauthApplication #{params[:oauth_application]} not found."
      end
    end

    if params[:integration].present?
      if integration = Integration.find_by(id: params[:integration].strip)
        actors << Actor.new(object: integration, name: params[:integration])
      else
        errors << "Integration #{params[:integration]} not found."
      end
    end

    if params[:vulnerability].present?
      if vulnerability = Vulnerability.find_by(ghsa_id: params[:vulnerability].strip)
        actors << Actor.new(object: vulnerability, name: params[:vulnerability])
      else
        errors << "Security advisory #{params[:vulnerability]} not found."
      end
    end

    if params[:host].present?
      actors << Actor.new(
        object: GitHub::FlipperHost.new(params[:host].strip),
        name: params[:host],
      )
    end

    if params[:site].present?
      actors << Actor.new(
        object: GitHub::FlipperSite.new(params[:site].strip),
        name: params[:site],
      )
    end

    if params[:role].present?
      actors << Actor.new(
        object: GitHub::FlipperRole.new(params[:role].strip),
        name: params[:role],
      )
    end

    if params[:vexi_id].present?
      vexi_id = params[:vexi_id].strip

      if record = GitHub::VexiActor.from_vexi_id(vexi_id)
        actors << Actor.new(
          object: record,
          name: params[:vexi_id],
        )
      else
        errors << "VexiActor #{params[:vexi_id]} not found."
      end
    end

    ActorsFromParams.new(found: actors, users_not_found:, repos_not_found:, errors:)
  end

  def find_feature
    FlipperFeature.find_by!(name: params[:feature_flag_id] || params[:id])
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def flipper_feature_params
    params.require(:flipper_feature).permit(
      :name,
      :long_lived,
      :description,
      :slack_channel,
      :github_org_team_id,
      :tracking_issue_url,
      :stale_at,
      :service_name
    )
  end

  def record_metric(metric_name, feature_name, tags = nil)
    base_tags = [
      "name:#{feature_name}",
      "user_hash:#{current_user.id.to_s.hash.to_s(16)}",
      "proxima:#{GitHub.multi_tenant_enterprise?}"
    ]

    if tags.present? && tags.is_a?(String)
      base_tags = base_tags.append(tags)
    elsif tags.present? && tags.is_a?(Array)
      base_tags.concat(tags)
    end

    GitHub.dogstats.increment(metric_name, tags: base_tags)
  end

  def analyze_gate_update(concurrency_error)
    return :error_concurrency if concurrency_error
    :success
  end

  def create_gate_flash(gate, status, failed_syncs = [], enabled = false)
    case status
    when :success_with_sync
      {
        notice: "#{gate[:change_type]} '#{gate[:feature_name]}' for #{gate[:change_scope]} in all stamps. #{TTL_WARNING}",
        celebrate: enabled,
      }
    when :success
      {
        notice: "#{gate[:change_type]} '#{gate[:feature_name]}' for #{gate[:change_scope]} in dotcom only. #{TTL_WARNING}",
        celebrate: enabled,
      }
    when :error_partial_update
      {
        error: "#{gate[:change_type]} '#{gate[:feature_name]}' for #{gate[:change_scope]} in dotcom but failed on the following stamps: #{failed_syncs.join(", ")}. #{TTL_WARNING}",
      }
    when :error_concurrency_with_sync
      {
        error: "#{STALE_ETAG_WARNING}. The update was applied to other stamps."
      }
    when :error_concurrency_with_partial_sync
      {
        error: "#{STALE_ETAG_WARNING}. The update may have been applied to other stamps."
      }
    when :error_concurrency
      {
        error: STALE_ETAG_WARNING
      }
    end
  end

  def param_date(date)
    Date.parse(date)
  rescue ArgumentError
    nil
  end

  def param_datetime(date)
    DateTime.parse(date)
  rescue ArgumentError
    nil
  end
end

# rubocop:enable GitHub/FeatureManagement/NoFlipperFeatureUsage
