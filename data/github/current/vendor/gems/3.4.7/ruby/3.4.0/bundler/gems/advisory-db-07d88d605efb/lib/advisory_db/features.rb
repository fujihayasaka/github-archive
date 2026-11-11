# frozen_string_literal: true

# this file exists as a guard around the use of the dotcom features exposed by config/initializers/feature_flags.rb
# because there isn't safety guards, we drive everything through this API.
module AdvisoryDB
  module Features
    def self.feature_enabled_in_development?(feature_name)
      %w[
        advisory_db_advisory_batch_edit
        advisory_db_advisory_review_grouped_buttons
        advisory_db_affected_functions_v1
        advisory_db_cve_reviews_reject_published
        advisory_db_cvss_v4
        advisory_db_purl_ecosystems_inbox
        advisory_db_structured_payload_double_write
      ].include?(feature_name)
    end

    # returns if a feature is enabled
    # for_user_ids is an array of monolith user ids (unlikely to apply to advisory-db as is)
    # for_repository_ids is an array of monolith repository ids (would require mapping from NWO to repository id)
    def self.enabled?(feature_name, for_user_login: nil, for_repository_ids: nil)
      if Rails.env.development? && feature_enabled_in_development?(feature_name)
        return true
      end

      actors = []
      if for_user_login.present?
        begin
          user_id = get_cached_or_fetch("user_id_for_login", for_user_login, 1.hour) do
            AdvisoryDB.github.user(for_user_login).id
          end
          actors.push FeatureFlags::Actor::User.new(user_id)
        rescue StandardError => error
          Failbot.report!(error)
          # We do nothing else here, effectively allowing normal feature logic to function if we can't lookup the user.
        end
      end

      if for_repository_ids.present?
        for_repository_ids.each { |rid| actors.push FeatureFlags::Actor::Repository.new(rid) }
      end

      begin
        if actors.count == 0
          AdvisoryDB::Application.flipper[feature_name].enabled?
        else
          AdvisoryDB::Application.flipper[feature_name].enabled?(*actors)
        end
      rescue StandardError => error
        # Report errors that happen here but treat it like features are disabled.
        # This means we don't expect long lived features, and if the feature service goes down
        # we may see features shut off but our service will still function.
        # During test, do not report the error since it is expected.
        Failbot.report!(error, { feature_name: feature_name }) unless Rails.env.test?
        false
      end
    end

    def self.get_cached_or_fetch(operation, data_key, expiration)
      cache_key = ["github_features", Rails.env, operation, data_key].join(":")
      user_id = AdvisoryDB.redis.get(cache_key)
      if user_id.nil?
        user_id = yield
        AdvisoryDB.redis.set(cache_key, user_id, ex: expiration.to_i)
      end

      user_id
    end
  end
end
