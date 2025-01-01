# typed: true
# frozen_string_literal: true

module User::UnwatchSuggestionsDependency
  extend T::Helpers
  include Platform::Helpers::Newsies

  requires_ancestor { User }

  def unwatch_suggestions_response(cap_filter)
    T.bind(self, User)

    return if dismissed_unwatch_suggestions?

    Platform::Security::RepositoryAccess.with_viewer(self) do
      { suggestions: async_unwatch_suggestions(cap_filter).sync }
    end
  rescue Platform::Errors::ServiceUnavailable
    { error: true }
  end

  # Public - fetch this user's unwatch suggestions, sorted by score
  #
  # cap_filter - the filter used to filter out repositories that the user should
  #              not see suggestions for
  #
  # Returns: Promise([Munger::Client::DataUnsubscribeSuggestion])
  def async_unwatch_suggestions(cap_filter)
    # If for some reason this method is called with a user who has dismissed
    # their unwatch suggestions, then we don't need to do any more work, we just return
    # an empty results set.
    return Promise.resolve([]) if self.dismissed_unwatch_suggestions?

    # Grab unwatch suggestions from munger - results are limited to 10.
    suggestions_hash = begin
      GitHub.munger.notifications_unsubscribe_suggestions(self)&.index_by(&:repository_id)
    rescue => e # rubocop:todo Lint/GenericRescue
      NotificationsFailbot.report(e, user: self)
      nil
    end

    if !suggestions_hash.present?
      # Unwatch suggestions are updated daily, if the user does not have any
      # suggestions there is no need to keep querying munger for data. This
      # saves us $$$ and milliseconds by reducing the number of round trips
      # to munger on each request.
      ActiveRecord::Base.connected_to(role: :writing) do
        self.set_dismissed_unwatch_suggestions(expiry_time: 1.day.from_now)
      end

      return Promise.resolve([])
    end

    # The user could have unsubscribed from the list between when the munger suggestions were created
    # and when the user receives the suggestions. In order to make sure that we don't show suggestions for
    # out of date subscriptions we ensure that we only return suggestions where the user still has a subscription
    # to the repository.
    lists = suggestions_hash.keys[0..9].map do |repository_id|
      Newsies::List.new(Newsies::List.type_from_class(Repository), repository_id)
    end

    user_subscriptions_for_suggestions = handle_newsies_service_unavailable do
      Newsies::ListSubscription
        .for_user(self)
        .for_lists(lists)
        .excluding_ignored
    end
    return Promise.resolve([]) if user_subscriptions_for_suggestions.empty?

    async_notification_unwatch_suggestions_with_repos = user_subscriptions_for_suggestions.filter_map do |subscription|
      suggestion = suggestions_hash[subscription.list_id]

      async_repository = Platform::Loaders::ActiveRecord.load(Repository, suggestion.repository_id.to_i, security_violation_behaviour: :nil)
      async_repository.then do |repo|
        if repo && suggestion.user_id == self.id
          repo.async_readable_by?(self).then do |readable|
            suggestion.repository = repo
            next suggestion if readable
          end
        end
      end
    end

    Promise.all(async_notification_unwatch_suggestions_with_repos).then do |suggestions|
      suggestions.compact!
      repositories = suggestions.map(&:repository)

      repository_ids = if cap_filter
        # Filter suggestions by the current conditional access filter.
        # For example, this removes repositories behind SSO when the current viewer
        # is not logged in using such SSO.
        cap_filter.authorized_resource_ids(repositories.compact)
      else
        # If there is no CAP filter default to only public repositories
        repositories.filter_map { |r| r.id if r.public? }
      end

      filtered_suggestions = suggestions.select { |s| s && repository_ids.include?(s.repository_id) }

      filtered_suggestions.sort_by(&:score).reverse
    end
  end
end
