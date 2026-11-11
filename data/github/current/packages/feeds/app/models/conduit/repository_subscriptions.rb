# typed: true
# frozen_string_literal: true

module Conduit
  class RepositorySubscriptions
    SUBSCRIPTION_LIMIT = 500

    # for_user fetches the repository subscriptions for a given user.
    # If the user has over 1000 subscriptions, it will return the first 1000 subscribed repos.
    def self.for_user(user, limit: SUBSCRIPTION_LIMIT)
      newsies = Newsies::Service.new
      repositories = newsies.subscribed_repositories(
        user, set: :subscribed, page: 1, per_page: limit, sort: :desc
      ).value!

      repositories.map do |repository|
        MonolithTwirp::Conduit::Feeds::V1::RepositorySubscription.new(
          repository_id: repository.id,
          subscription_type: "list",
        )
      end
    end
  end
end
