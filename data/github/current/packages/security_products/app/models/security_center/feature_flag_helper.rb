# typed: strict
# frozen_string_literal: true

module SecurityCenter::FeatureFlagHelper
  extend T::Sig

  Actor = T.type_alias { T.any(User, Repository, Organization, Business) }

  sig { params(base: Module).returns(T.noreturn) }
  def self.included(base)
    raise StandardError.new "Don't include this module. Use the fully-qualified name."
  end

  sig { params(base: Module).returns(T.noreturn) }
  def self.extended(base)
    raise StandardError.new "Don't extend this module. Use the fully-qualified name."
  end

  sig { params(base: Module).returns(T.noreturn) }
  def self.prepended(base)
    raise StandardError.new "Don't prepend this module. Use the fully-qualified name."
  end

  # This is not a feature flag
  # For users, we need to make sure they belong to an enterprise managed business.
  # For businesses, they must be enterprise managed.
  sig { params(actor: T.any(User, Business)).returns(T::Boolean) }
  def self.allows_emu_owned_repositories?(actor)
    if actor.is_a?(Business)
      AdvancedSecurity::Features::Business::AdvancedSecurity.new(actor).security_center_for_emus_enabled?
    elsif actor.user?
      AdvancedSecurity::Features::User::AdvancedSecurity.new(actor).security_center_for_emus_enabled?
    else
      false
    end
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.no_visible_features_for_non_emu_owners?(*actors)
    feature_flag :security_center_show_no_visible_features_for_non_emu_owners, actors: actors
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.in_private_beta?(*actors)
    any_actor?(actors) { |actor| actor.feature_enabled?(:security_center_private_beta) }
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.security_center_feedback_link_enabled?(*actors)
    feature_flag :security_center_feedback_link, actors: actors
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.show_codeql_pr_alerts_export?(*actors)
    return false if GitHub.enterprise?
    feature_flag :security_center_show_codeql_pr_alerts_export, actors:
  end

  sig { params(widget_name: Symbol, actors: Actor).returns(T::Boolean) }
  def self.dashboards_show_widget?(widget_name, *actors)
    widget_names = [
      :sast_table,
    ]
    raise "Unknown widget name" unless widget_names.include?(widget_name)

    if [:reopened_alerts_card, :advisories_table].include?(widget_name) && GitHub.enterprise?
      return true
    end

    feature_flag "security_center_dashboards_show_#{widget_name}".to_sym, actors: actors
  end

  sig { params(filter_name: Symbol, actors: Actor).returns(T::Boolean) }
  def self.dashboards_show_filter?(filter_name, *actors)
    filter_names = [
      :severity,
      :resolution,
    ]
    raise "Unknown filter name" unless filter_names.include?(filter_name)

    return true if GitHub.enterprise? && filter_name == :severity

    feature_flag "security_center_dashboards_show_#{filter_name}_filter".to_sym, actors: actors
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.show_code_scanning_linked_alerts?(*actors)
    feature_flag :security_center_show_code_scanning_linked_alerts, actors: actors
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.overview_dashboard_csv_export?(*actors)
    feature_flag :security_center_overview_dashboard_csv_export, actors: actors
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.csv_export_use_rate_limiter?(*actors)
    feature_flag :security_center_csv_export_use_rate_limiter, actors: actors
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.dashboards_cards_parallel_queries_per_tool?(*actors)
    feature_flag :security_center_dashboards_cards_parallel_queries_per_tool, actors: actors
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.show_repo_id_in_alert_prioritization_experiment_csv?(*actors)
    feature_flag :show_repo_id_in_alert_prioritization_experiment_csv, actors: actors
  end

  # When enabled for an actor, ::SecurityCenter::AlertPrioritization::CopilotPromptExperiments::OwnerCsvJob will stop processing that actor's repositories.
  sig { params(actors: Actor).returns(T::Boolean) }
  def self.disable_alert_prioritization_owner_csv_job?(*actors)
    feature_flag :disable_alert_prioritization_owner_csv_job, actors: actors
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.alert_prioritization_owner_csv_job_ui_enabled?(*actors)
    feature_flag :alert_prioritization_owner_csv_job_ui, actors: actors
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.disable_alert_prioritization_owner_trigger_embeddings_indexing_job?(*actors)
    feature_flag :disable_alert_prioritization_owner_trigger_embeddings_indexing_job, actors: actors
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.show_unified_alerts?(*actors)
    feature_flag :security_center_unified_alerts, actors:
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.dashboards_parallel_queries_by_4_slices?(*actors)
    feature_flag :security_center_overview_dashboard_parallel_queries_by_4_slices, actors: actors
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.fetch_stafftool_alert_count_async?(*actors)
    feature_flag :security_center_fetch_stafftool_alert_count_async, actors: actors
  end

  sig { params(business: Business).returns(T::Boolean) }
  def self.show_enterprise_security_manager_assignment_page?(business)
    return false unless business.enterprise_teams_enabled?
    return false unless EnterpriseTeam.enabled_for_organization_security_manager?(business)
    return GitHub.esm_enabled? if GitHub.enterprise?

    feature_flag :security_center_show_enterprise_security_manager_assignment_page, actors: [business]
  end

  sig { params(business: Business).returns(T::Boolean) }
  def self.show_enterprise_security_manager_assignment_page_to_all_members?(business)
    return true if GitHub.enterprise?
    return false unless show_enterprise_security_manager_assignment_page?(business)

    feature_flag :security_center_show_enterprise_security_manager_assignment_page_to_all_members, actors: [business]
  end


  sig { params(actors: Actor).returns(T::Boolean) }
  def self.show_three_tab_dashboard?(*actors)
    feature_flag :security_center_dashboards_show_three_tab_dashboard, actors: actors
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.use_introduced_and_prevented_chart_query_v2?(*actors)
    feature_flag :security_center_use_introduced_and_prevented_chart_query_v2, actors: actors
  end

  # Determines whether the given feature is enabled for any of the given actors.
  # Also handles private beta feature enablement.
  #
  # NOTE: Do not rename. This name satisfies the "feature_flags_are_used" lint test without forcing us to duplicate this logic.
  sig { params(feature: Symbol, actors: T::Array[Actor]).returns(T::Boolean) }
  def self.feature_flag(feature, actors:)
    started_at = GitHub::Dogstats.monotonic_time
    tags = { feature: feature }

    feature_private_beta_flag = FlipperFeature.find_by(name: "#{feature}_private_beta")
    feature_enabled_for_private_beta = feature_private_beta_flag&.fully_enabled?

    feature_enabled = any_actor?(actors) do |actor|
      tags[:actor_type] = actor.class.name&.demodulize.underscore

      # the actor is enabled for the feature, either directly or indirectly via group membership
      next true if actor.feature_enabled?(feature)

      # the actor is in the private beta "group", and the feature is enabled for private beta
      # This workaround supports "groups" of arbitrary actors, without requiring
      #   - team membership, which limits to only User actors
      #   - any new models
      next true if feature_enabled_for_private_beta && actor.feature_enabled?(:security_center_private_beta)

      false
    end

    if actors.empty? && !feature_enabled
      feature_flag = GitHub.flipper[feature]
      feature_enabled = feature_flag.enabled? || feature_flag.percentage_of_actors_value == 100
    end

    tags[:result] = feature_enabled

    GitHub.dogstats.distribution(
      "security_center.feature_flag.dist",
      GitHub::Dogstats.duration(started_at),
      tags: tags.map { |k, v| "#{k}:#{v}" }
    )

    feature_enabled
  end

  sig do
    params(
      actors: T::Array[Actor],
      blk: T.proc.params(actor: Actor).returns(T::Boolean) # https://sorbet.org/docs/procs#annotating-methods-that-use-yield
    ).returns(T::Boolean)
  end
  def self.any_actor?(actors, &blk)
    actors.each do |actor|
      if actor.is_a?(Repository)
        return true if yield actor
        actor = actor.owner
      end

      if actor.is_a?(Organization)
        return true if yield actor
        actor = actor.business
      end

      if actor.is_a?(Business)
        return true if yield actor
      end

      if actor.is_a?(User)
        return true if yield actor
      end
    end

    false
  end
end
