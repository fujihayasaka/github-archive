require "monolith-twirp-features-core"
require_relative "twirp_client"

# Copied from https://github.com/github/monolith-twirp-features/blob/main/examples/ruby/lib/example/client.rb

module Monolith
  class Features < TwirpClient
    def initialize
      super(service: "github-features")
      @enabled = true
    rescue ConfigNotFoundError => e
      # This might happen in Enterprise environments, or somewhere else the MONOLITH_API_URL isn't set.
      DependencyGraph.logger.info("Error enabling Features client. Features will be disabled.", e)
      @enabled = false
    end

    # Actor IDs are formatted as [actor_type]:[actor_id], i.e. "User:2"
    # If timeouts or other errors occur, we will run the fallback conditional defined.
    # We will log the error and increment a DataDog counter for timeouts.
    #
    # Having the fallback default to `false` means that when the flag is inaccessible, we treat it as "off"
    def feature_enabled?(actor_id: nil, feature:, fallback: false)
      if !@enabled
        Instrument.increment("feature_enabled.fallback",
                             feature: feature,
                             enabled: @enabled,
                             method: "feature_enabled?")
        return fallback
      end

      resp = if actor_id
               client.check_actor_feature(actor_id: actor_id, feature: feature)
             else
               client.check_global_feature(feature: feature)
             end

      if resp.error
        feature_fetching_error = Error.new resp.error
        Failbot.report(feature_fetching_error, :feature => feature, "gh.user_or_repo_id" => actor_id)
        return fallback
      end

      res = resp.data.is_enabled
      return res

    rescue Faraday::TimeoutError => e
      Instrument.increment("feature_enabled.fallback",
                           feature: feature,
                           enabled: @enabled,
                           method: "feature_enabled?",
                           error: e.class.name.demodulize.underscore)
      Failbot.report(e, "feature_flag.key" => feature, "gh.user_or_repo_id" => actor_id)
      return fallback
    end

    def feature_enabled_for_repo?(github_repository_id:, feature:)
      repo_actor = "Repository:#{github_repository_id}"

      feature_enabled?(actor_id: repo_actor, feature: feature)
    end

    def feature_enabled_for_repo_owner?(github_owner_id:, feature:)
      owner_actor = "User:#{github_owner_id}"

      feature_enabled?(actor_id: owner_actor, feature: feature)
    end

    def feature_enabled_for_all_users?(github_user_ids:, feature:)
      users = github_user_ids.map { |uid| "User:#{uid}" }
      all_actors_feature(actor_ids: users, feature:)
    end

    # Given a list of actor IDs of the form "Model:111" return true if ANY are enabled
    def any_actors_feature(actor_ids:, feature:)
      check_actors_feature(actor_ids: actor_ids, feature: feature).map { |r| r.is_enabled }.any?
    end

    # Given a list of actor IDs of the form "Model:111" return true if ALL are enabled
    def all_actors_feature(actor_ids:, feature:)
      check_actors_feature(actor_ids: actor_ids, feature: feature).map { |r| r.is_enabled }.all?
    end

    # Returns an array of ActorFeatureResults you can call is_enabled on,
    # or an array of the same (one for each actor input) all set to "false"
    # as a fallback.
    def check_actors_feature(actor_ids:, feature:)
      if !@enabled
        Instrument.increment("feature_enabled.fallback",
                             feature: feature,
                             enabled: @enabled,
                             method: "check_actors_feature")
        return multi_actor_fallback(actor_ids)
      end

      resp = client.check_actors_feature(actor_ids: actor_ids, feature: feature)

      if resp.error
        feature_fetching_error = Error.new resp.error
        Failbot.report(feature_fetching_error, :feature => feature, "gh.user_or_repo_id_list" => actor_ids)
        return multi_actor_fallback(actor_ids)
      end

      return resp.data.results

    rescue Faraday::TimeoutError => e
      Instrument.increment("feature_enabled.fallback",
                           feature: feature,
                           enabled: @enabled,
                           method: "check_actors_feature",
                           error: e.class.name.demodulize.underscore)
      Failbot.report(e, "feature_flag.key" => feature, "gh.user_or_repo_id_list" => actor_ids)
      return multi_actor_fallback(actor_ids)
    end

    private

    def multi_actor_fallback(actor_ids)
      actor_ids.to_a.map { |a| MonolithTwirp::Features::Core::V1::ActorFeatureResult.new(actor_id: a, is_enabled: false) }
    end

    def client
      @client ||= MonolithTwirp::Features::Core::V1::FeaturesAPIClient.new(connection)
    end
  end
end
