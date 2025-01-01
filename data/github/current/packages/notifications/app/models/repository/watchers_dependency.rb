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

      count_subscribers_response = GitHub.newsies.count_subscribers(self, exclude_spammy_users: true)
      raise count_subscribers_response.error if count_subscribers_response.failed?

      subscribers_response = GitHub.newsies.subscribers(self, page: page, per_page: per_page, exclude_spammy_users: true)
      raise subscribers_response.error if subscribers_response.failed?

      size = count_subscribers_response.count
      WillPaginate::Collection.create(page, per_page, size) do |pager|
        pager.replace(subscribers_response.value)
      end
    end
  end

  # Returns the number of users watching this repo.
  def watchers_count
    @watchers_count ||= GitHub.newsies.count_subscribers(self, exclude_spammy_users: true).count
  end

  def auto_subscribe_owners
    owners = owner.organization? ? owner.admins : [owner]
    GitHub.newsies.async_subscribe_users_to_repository(self.id, owners.map(&:id), created_by_user_id)
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
