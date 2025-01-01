# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module FeatureFlagHelper
    extend T::Sig

    Actor = T.type_alias { T.any(User, ::Repository, ::Organization, ::Business) }

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

    sig { params(actors: Actor).returns(T::Boolean) }
    def self.in_private_beta?(*actors)
      any_actor?(actors) { |actor| actor.feature_enabled?(:security_center_private_beta) }
    end

    sig { params(actors: Actor).returns(T::Boolean) }
    def self.cs_and_dbot_regularly_scheduled_full_reconciliation?(*actors)
      feature_flag :security_overview_analytics_cs_and_dbot_regularly_scheduled_full_reconciliation, actors:
    end

    sig { params(actors: Actor).returns(T::Boolean) }
    def self.incremental_deviation_reporting_enabled?(*actors)
      feature_flag :security_overview_analytics_incremental_deviation_reporting_enabled, actors: actors
    end

    sig { params(actors: Actor).returns(T::Boolean) }
    def self.reconciliation_total_counts_check?(*actors)
      feature_flag :security_overview_analytics_reconciliation_total_counts_check, actors: actors
    end

    sig { params(filter_name: Symbol, actors: Actor).returns(T::Boolean) }
    def self.use_alerts_filterer_class?(filter_name, *actors)
      filter_names = [
        :severity,
        :resolution,
      ]
      raise "Unknown filter name" unless filter_names.include?(filter_name)

      return true if GitHub.enterprise? && filter_name == :severity

      feature_flag "security_overview_analytics_alert_filterer_class_#{filter_name}".to_sym, actors: actors
    end

    sig { returns(T::Boolean) }
    def self.handle_changed_advisory_job_run_two_part_query?
      GitHub.flipper[:security_overview_analytics_run_two_part_query].enabled?
    end

    sig { params(actors: Actor).returns(T::Boolean) }
    def self.code_scanning_read_alert_id?(*actors)
      feature_flag :security_overview_analytics_code_scanning_read_alert_id, actors: actors
    end

    sig { params(actors: Actor).returns(T::Boolean) }
    def self.code_scanning_read_alert_number?(*actors)
      feature_flag :security_overview_analytics_code_scanning_read_alert_number, actors: actors
    end

    sig { params(actors: Actor).returns(T::Boolean) }
    def self.code_scanning_write_alert_number?(*actors)
      feature_flag :security_overview_analytics_code_scanning_write_alert_number, actors: actors
    end

    sig { params(actors: Actor).returns(T::Boolean) }
    def self.code_scanning_reconciliation_dry_run_mode?(*actors)
      feature_flag :security_overview_analytics_code_scanning_reconciliation_dry_run, actors: actors
    end

    sig { params(actors: Actor).returns(T::Boolean) }
    def self.code_scanning_purge_redundant_revisions?(*actors)
      feature_flag :security_overview_analytics_code_scanning_purge_redundant_revisions, actors: actors
    end

    sig { params(actors: T.nilable(Actor)).returns(T::Boolean) }
    def self.report_duplicate_revisions?(*actors)
      feature_flag :security_overview_analytics_report_duplicate_revisions, actors: actors.compact
    end

    sig { params(actors: Actor).returns(T::Boolean) }
    def self.run_data_compression?(*actors)
      feature_flag :security_overview_analytics_run_data_compression, actors: actors
    end

    sig { params(scope: T.any(::User, ::Organization)).returns(T::Boolean) }
    def self.allow_data_cleanup?(scope)
      return true if GitHub.enterprise?
      feature_flag :security_center_allow_data_cleanup, actors: [scope]
    end

    sig { params(actors: T.nilable(Actor)).returns(T::Boolean) }
    def self.write_to_elasticsearch?(*actors)
      feature_flag :security_overview_analytics_write_to_elasticsearch, actors: actors.compact
    end

    sig { params(actors: T.nilable(Actor)).returns(T::Boolean) }
    def self.dashboard_repos_load_async?(*actors)
      feature_flag :security_overview_analytics_dashboard_repos_load_async, actors: actors.compact
    end

    sig { params(actors: T.nilable(Actor)).returns(T::Boolean) }
    def self.enablement_trends_load_async?(*actors)
      feature_flag :security_overview_analytics_enablement_trends_load_async, actors: actors.compact
    end

    sig { params(actors: Actor).returns(T::Boolean) }
    def self.check_for_user_repositories?(*actors)
      return true if GitHub.enterprise?
      feature_flag :security_overview_analytics_check_for_user_repositories, actors: actors
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
        if actor.is_a?(User) && !actor.is_a?(Organization)
          return true if yield actor
        end

        if actor.is_a?(::Repository)
          return true if yield actor
          actor = actor.owner
        end

        if actor.is_a?(::Organization)
          return true if yield actor
          actor = actor.business
        end

        if actor.is_a?(::Business)
          return true if yield actor
        end
      end

      false
    end
  end
end
