# typed: false
# frozen_string_literal: true

module Repository::WatchersDependency
  # List of users watching this repository. If passed an Integer,
  # returns a paginated slice. Otherwise returns everyone.
  #
  # page - The optional Integer page number. Respects this class's
  #        per_page.
  #
  # Returns a Newsies::Responses::WillPaginateCollection of User objects.
  def watchers(page = nil, per_page = 100)
    Newsies::Responses::WillPaginateCollection.new do
      page = [page.to_i, 1].max

      count_subscribers_response = Notifications::Subscriptions.count_repository_subscribers(id, exclude_spammy_users: true)
      raise Resiliency::Response::UnavailableError, "Failed to count repository subscribers" if count_subscribers_response.nil?

      subscribers_response = Notifications::Subscriptions.repository_subscribers_by_page(self, page: page, per_page: per_page)
      raise Resiliency::Response::UnavailableError, "Failed to fetch repository subscribers" if subscribers_response.nil?

      size = count_subscribers_response
      WillPaginate::Collection.create(page, per_page, size) do |pager|
        pager.replace(subscribers_response)
      end
    end
  end

  # Returns the number of users watching this repo.
  def watchers_count
    @watchers_count ||= Notifications::Subscriptions.count_repository_subscribers(id, exclude_spammy_users: true) || 0
  end

  # After destroy callback to delete all newsfeed data for the repository.
  def delete_all_newsies_data
    Notifications::Subscriptions.async_delete_list_subscriptions(Notifications::Subject.new(type: self.class.name, id: self.id))
  end

  # Internal: Remove newsies records for users who no longer have access.
  def correct_watchers
    async_purge_subscribers unless public?
  end
end
