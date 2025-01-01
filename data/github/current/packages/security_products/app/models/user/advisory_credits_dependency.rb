# typed: true
# frozen_string_literal: true

module User::AdvisoryCreditsDependency
  extend T::Helpers
  requires_ancestor { User }

  def global_advisory_credit_count
    GitHub.cache.fetch(
      "user:global_advisory_credit_count:#{id}",
      ttl: 1.hour,
      stats_key: "user.cache.global_advisory_credit_count",
    ) do
      # First we check the database for *any* advisory credits associated with
      # this user. Most users have none so this saves us a ~10-15ms round trip
      # to Elasticsearch. If the user does have credits, we fetch the count from
      # Elasticsearch because it's the source of truth for public, global
      # security advisories and their public credits.
      if advisory_credits.any?
        Search::QueryHelper.new("credit:#{login}", "Vulnerabilities", {}).
          vulnerability_query.
          count
      else
        0
      end
    end
  end
end
