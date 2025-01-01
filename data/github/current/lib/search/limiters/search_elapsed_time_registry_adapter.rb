# typed: true
# frozen_string_literal: true

module Search::Limiters::SearchElapsedTimeRegistryAdapter
  extend ActiveSupport::Concern
  include Kernel
  include Search::RateLimitRegistry

  included do
    # Limit search query execution time to a maximum of 4000ms per window across
    # all searchables in queries initiated in both the search API endpoints and
    # the two frontend search controllers.
    this = T.cast(self, Class)
    register_search_rate_limiter \
      Search::Limiters::SearchElapsedTime.new(
        name: "search-elapsed-time-shared-grouped",
        limit: GitHub.search_elapsed_time_max,
        ttl: GitHub.search_elapsed_time_ttl,
        strategy: :grouped, context: (this <= Sinatra::Base ? :api : :web)
      ),
      start_request: :search_elapsed_time_start,
      finish_request: :search_elapsed_time_finish,
      # RepositorySearchController and CodesearchController will use :only
      only: (this <= Sinatra::Base ? nil : :index),
      if: :limit_search_elapsed_time_user?

    # Ditto but for staff
    # Temporary workaround until we can unwrap `limit` as an instance attribute
    register_search_rate_limiter \
      Search::Limiters::SearchElapsedTime.new(
        name: "search-elapsed-time-shared-grouped-staff",
        limit: GitHub.search_elapsed_time_staff_max,
        ttl: GitHub.search_elapsed_time_ttl,
        strategy: :grouped, context: (this <= Sinatra::Base ? :api : :web)
      ),
      start_request: :search_elapsed_time_start,
      finish_request: :search_elapsed_time_finish,
      only: (this <= Sinatra::Base ? nil : :index),
      if: :limit_search_elapsed_time_staff?
  end

  def limit_search_elapsed_time_user?
    !search_elapsed_time_user_is_staff? && limit_search_elapsed_time?
  end

  def limit_search_elapsed_time_staff?
    search_elapsed_time_user_is_staff? && limit_search_elapsed_time?
  end

  def search_elapsed_time_user_is_staff?
    T.bind(self, T.untyped)
    logged_in? && current_user.employee?
  end

  def limit_search_elapsed_time?
    # Some users are exempt from rate limiting
    T.bind(self, T.untyped)
    return false if logged_in? && current_user.rate_limit_exempt_user?

    # Can't check query cost in server time if there's no query, amiright?
    if self.is_a?(Api::Search)
      params[:q] && params[:q].to_s.dup.force_encoding("UTF-8").valid_encoding?
    else
      params[:q].present?
    end
  end

  def search_elapsed_time_start(limiter, _state)
    T.bind(self, T.untyped)
    actor_id = logged_in? ? current_user.id : search_elapsed_time_remote_ip
    auth_state = logged_in? ? "auth" : "anon"
    tags = [
      "controller:#{self.class.to_s.parameterize.gsub("controller", "")}",
      "logged_in:#{auth_state}"
    ]

    search_type = search_elapsed_time_search_type
    if limiter.at_limit?(actor_id, search_type, tags)
      tags += ["search_type:#{search_type.downcase}"]
      limiter.stat("ratelimited", tags)
      limiter.publish(actor: current_user, halted: true,
                      search_type: search_type)
      render_search_rate_limiter_halt!(limiter.name)
    else
      :OK
    end
  end

  def search_elapsed_time_finish(limiter, _state)
    T.bind(self, T.untyped)
    actor_id = logged_in? ? current_user.id : search_elapsed_time_remote_ip
    auth_state = logged_in? ? "auth" : "anon"
    tags = [
      "controller:#{self.class.to_s.parameterize.gsub("controller", "")}",
      "logged_in:#{auth_state}"
    ]

    # Increment the limiter with the new search time
    search_type = search_elapsed_time_search_type
    limiter.increment(actor_id, search_type, tags)
  end

  # Each controller determines this a little bit differently.
  def search_elapsed_time_search_type
    if self.is_a?(RepositorySearchController)
      # Use the defined type method which works based on type param
      type
    elsif self.is_a?(CodesearchController)
      # Global search lets the QueryHelper determine the final search type
      queries.search_type
    elsif self.is_a?(Api::Search)
      # Use the search_type method which works based on requested path
      search_type
    else
      raise NotImplementedError
    end
  end

  # Handles difference between ActionController::Base and Sinatra::Base
  def search_elapsed_time_remote_ip
    if self.class <= ActionController::Base
      T.bind(self, T.untyped)
      request.remote_ip
    elsif self.class <= Sinatra::Base
      T.bind(self, T.untyped)
      remote_ip
    else
      raise NotImplementedError
    end
  end
end
