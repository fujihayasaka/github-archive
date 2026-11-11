# typed: false
# frozen_string_literal: true

module Newsies
  # Responsible for storing and retrieving the subscribers of lists.
  class ListSubscription < ApplicationRecord::Domain::Notifications
    self.table_name = :notification_subscriptions
    self.utc_datetime_columns = [:created_at]
    self.record_timestamps = false

    VALID_SORT = ["asc", :asc, "desc", :desc]

    DEFAULT_PAGE_SIZE = 100
    MAX_PAGE_SIZE = 1000

    validates :user_id, presence: true
    validates :list_type, presence: true
    validates :list_id, presence: true
    validates :ignored, inclusion: { in: [true, false] }

    belongs_to :list, polymorphic: true, foreign_key: :list_id, foreign_type: :list_type, optional: true

    SubscriberOptions = Options.new(:page, :per_page, :exclude_spammy_users) do
      def page
        @page ||= [self[:page].to_i, 1].max
      end

      def offset
        @offset ||= (page - 1) * per_page
      end
    end

    scope :for_list, ->(list) {
      raise ArgumentError, "list cannot be nil" unless list
      where(list_type: list.type, list_id: list.id)
    }

    # Subscriptions for multiple lists, may be of different list_types
    scope :for_lists, ->(lists) {
      raise ArgumentError, "lists cannot be nil" unless lists
      where(where_condition_for_lists(lists))
    }

    # Subscriptions excluding multiple lists, may be of different list_types
    scope :excluding_lists, ->(lists) {
      raise ArgumentError, "lists cannot be nil" unless lists
      where.not(where_condition_for_lists(lists))
    }

    scope :for_user, ->(user_id) {
      raise ArgumentError, "user_id cannot be nil" unless user_id
      where(user_id: user_id)
    }

    scope :for_users, ->(user_ids) {
      raise ArgumentError, "user_ids cannot be nil" unless user_ids
      where(user_id: user_ids)
    }

    scope :only_ignored, ->() {
      where(ignored: true)
    }

    scope :excluding_ignored, ->() {
      where(ignored: false)
    }

    scope :excluding_spammy_users, ->() {
      joins("LEFT JOIN hidden_users ON hidden_users.user_id = notification_subscriptions.user_id")
        .where("hidden_users.user_id IS NULL")
    }

    # Private: build a WHERE condition for multiple lists, with possibly different list_types
    # With multiple lists, we want to check `list_id IN (ids)`, but we must separate that
    # by list_type to ensure we get the right results
    #
    # Do not use directly, use via `for_lists` and `excluding_lists` scopes
    #
    # lists - An array of Newsies::List intances
    #
    # Returns ["(list_type = ? AND list_id IN (?)) OR ...", value_bindings]
    def self.where_condition_for_lists(lists)
      query_parts = []
      bindings = []
      lists.group_by(&:type).each do |(list_type, lists_of_type)|
        query_parts.push("(list_type = ? AND list_id IN (?))")
        bindings.push(list_type, lists_of_type.map(&:id).uniq)
      end
      [query_parts.join(" OR "), *bindings]
    end

    # Private: efficiently converts the current active record scope into an array of
    #          Subscriber objects
    #
    # Returns [Subscriber]
    def self.as_subscribers
      pluck(:user_id, :ignored, :created_at).map do |(user_id, ignored, created_at)|
        Subscriber.new(user_id, true, ignored, default_reason, created_at)
      end
    end

    # Private: efficiently converts the current active record scope into an array of
    #          Subscription objects
    #
    # Returns [Subscriber]
    def self.as_subscriptions
      includes(:list).map(&:as_subscription)
    end

    def as_subscription
      newsies_list = Newsies::List.new(list_type, list_id)
      subscription = Subscription.new(newsies_list, nil, true, ignored, self.class.default_reason, created_at)
      subscription.list_object = list
      subscription
    end

    # Public: Subscribes a User to a list, removing any ignore status.
    #
    # user_id - An Integer user id.
    # list    - A Newsies::List instance.
    #
    # Returns nothing.
    def self.subscribe(user_id, list)
      attributes = {
        user_id: user_id.to_i,
        list_id: list.id,
        list_type: list.type,
        created_at: Time.now.utc,
        ignored: false
      }
      upsert(attributes, on_duplicate: Arel.sql("`ignored` = 0"))
    end

    # Public: Returns valid Subscribers for this List.
    #
    # list    - A Newsies::List instance.
    # options - Optional SubscriberOptions or Hash.
    #           :page - Integer page number.  Default: 1
    #           :per_page - Integer per page. Default: DEFAULT_PAGE_SIZE
    #
    #
    # Returns an Array of Subscriber objects.
    def self.subscribers(list, options = nil)
      options = SubscriberOptions.from(options)
      options[:per_page] ||= DEFAULT_PAGE_SIZE
      options.per_page = [MAX_PAGE_SIZE, options[:per_page]].min

      scope = for_list(list)
                .excluding_ignored
                .offset(options.offset).limit(options.per_page)

      scope = scope.excluding_spammy_users if options.exclude_spammy_users

      results = scope.as_subscribers

      if options.exclude_spammy_users
        # Count spammy users within the unfiltered page window. We pluck the
        # user_ids from the unfiltered window and count how many are hidden.
        # Volume is very low (~0.2 req/sec) so no sampling needed.
        page_user_ids = for_list(list).excluding_ignored
                          .offset(options.offset).limit(options.per_page)
                          .pluck(:user_id)
        spammy_in_page = Newsies::HiddenUser.where(user_id: page_user_ids).count
        GitHub.dogstats.distribution(
          "newsies.subscribers.spammy_per_page",
          spammy_in_page,
          tags: ["list_type:#{list.type}"]
        )
      end

      results
    end

    # Public: Returns subscribers for a given list using cursor-based
    # pagination.
    #
    # list    - A Newsies::List instance.
    # options - Optional Hash.
    #           :cursor - Integer value that corresponds to a user_id.
    #           :cursor_direction - One of :upwards or :downwards. Used to
    #                               determine if the data to be returned should
    #                               be higher or lower than the cursor.
    #           :limit - Integer number of results to return.
    #           :excluding - An optional Array of list_ids to be excluded on the MySQL side.
    #
    # Examples
    #
    # Given the following subscribers pseudodata:
    #
    # ["Charlie", "Dee", "Dennis", "Frank", "Mac"]
    #
    # subscribers_by_cursor(list, :cursor => "Dennis", :cursor_direction => :upwards, :limit => 2)
    # # => ["Frank, "Mac"]
    #
    # subscribers_by_cursor(list, :cursor => "Dennis", :cursor_direction => :downwards, :limit => 2)
    # # => ["Charlie", "Dee"]
    #
    # Returns an Array of Subscriber objects.
    def self.subscribers_by_cursor(list, options = {})
      exclude_spammy = options[:exclude_spammy_users]
      cursor_direction = options[:cursor_direction]
      limit = options[:limit]

      scope = for_list(list).excluding_ignored
      scope = scope.excluding_spammy_users if exclude_spammy
      scope = scope.limit(limit) if limit

      case cursor_direction
      when :upwards
        scope = scope.where("#{table_name}.user_id > ?", options[:cursor]) if options[:cursor]
        scope = scope.order(user_id: :asc)
      when :downwards
        scope = scope.where("#{table_name}.user_id < ?", options[:cursor]) if options[:cursor]
        scope = scope.order(user_id: :desc)
      else
        scope = scope.order(user_id: :asc)
      end

      subscribers = scope.as_subscribers
      subscribers.reverse! if cursor_direction == :downwards
      subscribers
    end

    def self.apply_spammy_ratioing?
      rand < 0.001
    end

    # Public: Counts the valid Subscribers for this List.
    #
    # list                 - A Newsies::List instance.
    # exclude_spammy_users - A Boolean flag that will exclude Users marked as
    #                        spammy from the count.
    #
    # Returns an Integer count.
    def self.count(list, exclude_spammy_users = false)
      scope = for_list(list).excluding_ignored

      if exclude_spammy_users
        filtered_count = scope.excluding_spammy_users.count

        # Sample at 0.1% to measure the differential without impacting query load.
        # At ~7,000 req/sec this produces ~7 samples/sec — enough for meaningful
        # percentile distributions without meaningful performance impact.
        if self.apply_spammy_ratioing?
          unfiltered_count = scope.count
          spammy_count = unfiltered_count - filtered_count
          GitHub.dogstats.distribution(
            "newsies.count_subscribers.spammy_users_excluded",
            spammy_count,
            tags: ["list_type:#{list.type}"]
          )
          GitHub.dogstats.distribution(
            "newsies.count_subscribers.spammy_exclusion_ratio",
            unfiltered_count > 0 ? (spammy_count.to_f / unfiltered_count * 100).round(2) : 0,
            tags: ["list_type:#{list.type}"]
          )
        end

        filtered_count
      else
        scope.count
      end
    end

    # Public: Checks the user's subscription status of the list.
    #
    # user_id   - An Integer user id.
    # list      - A Newsies::List instance.
    #
    # Returns a Subscription object for the List.
    def self.status(user_id, list)
      list_subscription = for_user(user_id).for_list(list).first

      return Subscription.not_subscribed(list) unless list_subscription

      Subscription.new(list, nil, true, list_subscription.ignored, nil, list_subscription.created_at)
    end

    # Public: Checks an array of user's subscription status of the list.
    #
    # user_ids   - An array of Integer user ids.
    # list      - A Newsies::List.
    #
    # Returns an Array of Subscriptions for the List.
    def self.status_all(user_ids, list)
      subscriptions_by_user_id = fetch_subscriptions_for_users(user_ids, for_list: list)

      user_ids.map do |user_id|
        subscriptions_by_user_id[user_id] || Subscription.not_subscribed(list)
      end
    end

    # Public: Unsubscribes a User from a list and removes any ignore status.
    #
    # user_id - An Integer user ID.
    # lists   - An Array of Newsies::List instances.
    #
    # Returns nothing.
    def self.unsubscribe(user_id, lists)
      lists = Array(lists).compact
      return if lists.blank?

      for_user(user_id).for_lists(lists).delete_all

      nil
    end

    # Public: Sets the User to ignore a list.
    #
    # user_id   - An Integer user id.
    # list      - A Newsies::List instance.
    #
    # Returns nothing.
    def self.ignore(user_id, list)
      attributes = {
        user_id: user_id.to_i,
        list_id: list.id,
        list_type: list.type,
        ignored: true,
        created_at: Time.now.utc
      }
      upsert(attributes, on_duplicate: Arel.sql("`ignored` = 1"))
    end

    # Public: Checks to see which lists are ignored.
    #
    # user_id  - Integer User ID.
    # lists    - An Array of Newsies::List instances.
    #
    # Returns an Array of Subscription objects matching ignored lists.
    def self.ignored(user_id, lists)
      lists = Array(lists).compact
      return [] if lists.blank?

      fetch_subscriptions(user_id, for_lists: lists, set: :ignored)
    end

    # Public: Lists subscriptions that a User has.
    #
    # user_id   - An Integer user id.
    # list_type - Optional String that matches the list_id's type.
    # set       - Optional value to specify the set of subscriptions:
    #             :all        - All subscriptions and ignores (default).
    #             :subscribed - All subscriptions.
    #             :ignored    - All ignores.
    # page      - An optional Integer for which page to return.
    # per_page  - An optional Integer for how many results to return per page.
    # excluding - An optional Array of Newsies::List instances to be excluded on the MySQL side.
    # sort      - An optional String or Symbol direction to sort (:asc, "asc", :desc, "desc").
    #
    # Returns an Array of Notification::Subscription.
    def self.subscriptions(user_id, list_type: nil, set: nil, page: nil, per_page: nil, excluding: nil, sort: nil)
      fetch_subscriptions(user_id, list_type:, set:, page:, per_page:, excluding:, sort:)
    end

    def self.subscriptions_list_ids(user_id, list_type: nil, set: nil, page: nil, per_page: nil, excluding: nil, sort: nil)
      scope = subscriptions_scope(user_id, list_type: list_type, set: set, page: page, per_page: per_page, excluding: excluding, sort: sort)
      scope.pluck(:list_id)
    end

    def self.subscriptions_scope(user_id, list_type: nil, set: nil, page: nil, per_page: nil, excluding: nil, sort: nil)
      scope = for_user(user_id)
      scope = scope.where(list_type: list_type) if list_type

      case set
      when :subscribed
        scope = scope.excluding_ignored
      when :ignored
        scope = scope.only_ignored
      when nil, :all
      else
        raise ArgumentError, "Invalid set option: #{set.inspect}"
      end

      scope = scope.excluding_lists(excluding) if excluding.present?

      case sort
      when "created_at:asc"
        scope = scope.order(created_at: :asc)
      when *VALID_SORT
        scope = scope.order(id: sort.to_sym)
      when nil
        if page
          # backwards compatibility for previous api which did not allow
          # choosing sort, but forced a sort as soon as page was not nil
          scope = scope.order(id: :desc)
        end
      else
        raise ArgumentError, "Invalid sort option: #{sort} (valid: #{VALID_SORT.to_sentence})"
      end

      if page
        per_page ||= DEFAULT_PAGE_SIZE
        scope = scope
                  .offset((page - 1) * per_page)
                  .limit(per_page)
      end

      scope
    end

    # Public: Returns subscriptions for a given user using cursor-based
    # pagination.
    #
    # user_id - An Integer user id.
    # options - Optional Hash.
    #           :list_type - String list_type that matches the list_type
    #                        subscriptions to return. Default: "Repository"
    #           :cursor - Integer value that corresponds to a list_id.
    #           :cursor_direction - One of :upwards or :downwards. Used to
    #                               determine if the data to be returned should
    #                               be higher or lower than the cursor.
    #           :limit - Integer number of results to return.
    #           :excluding - An Array of Newsies::List instances to exclude.
    #
    # Examples
    #
    # Given the following subscriptions pseudodata:
    #
    # ["atom", "github", "hookshot", "hubot", "linguist"]
    #
    # subscriptions_by_cursor(1, :cursor => "hookshot", :cursor_direction => :upwards, :limit => 2)
    # # => ["hubot, "linguist"]
    #
    # subscriptions_by_cursor(1, :cursor => "hookshot", :cursor_direction => :downwards, :limit => 2)
    # # => ["atom", "github"]
    #
    # Returns an Array of Subscription objects.
    def self.subscriptions_by_cursor(user_id, options = {})
      fetch_subscriptions(
        user_id,
        list_type: options[:list_type] || "Repository",
        excluding: options[:excluding],
        cursor: options[:cursor],
        cursor_direction: options[:cursor_direction],
        limit: options[:limit]
      )
    end

    # Public: Count a user's subscriptions.
    #
    # user_id - An Integer user id.
    # set     - Optional value to specify the set of subscriptions:
    #           :all        - All subscriptions and ignores (default).
    #           :subscribed - All subscriptions.
    #           :ignored    - All ignores.
    # excluding - An optional Array of Newsies::List instances to be excluded on
    #             the MySQL side.
    # list_type - Optional String that matches the list_id's type.
    #
    # Returns an Integer count.
    def self.count_subscriptions(user_id, set: nil, excluding: nil, list_type: nil)
      scope = for_user(user_id)
      scope = scope.where(list_type: list_type) if list_type

      case set
      when :subscribed
        scope = scope.excluding_ignored
      when :ignored
        scope = scope.only_ignored
      when nil, :all
      else
        raise ArgumentError, "Invalid set option: #{set.inspect}"
      end

      scope = scope.excluding_lists(excluding) if excluding.present?
      scope.count
    end

    # Public: Allows iterating list subscriptions in batches.
    #
    # list - A Newsies::List instance.
    #
    # Yields Arrays of Newsies::Subscriber objects.
    # Returns nothing.
    def self.each(list, batch_size: 1000, &block)
      subscribers = nil
      max_queried_user_id = 0

      while !subscribers || subscribers.size >= batch_size
        subscribers = for_list(list)
                        .where("user_id > ?", max_queried_user_id)
                        .order(user_id: :asc)
                        .limit(batch_size)
                        .as_subscribers

        max_queried_user_id = subscribers.last.try(:user_id)

        block.call(subscribers) unless subscribers.empty?
      end
    end

    # Public: The default reason for for a subscriber/subscription.
    #
    # Returns a String.
    def self.default_reason
      "list"
    end

    # Private: Fetches subscriptions for multiple users for a single list.
    # Used by status_all to check subscription status for multiple users.
    #
    # user_ids - An Array of Integer user ids.
    # for_list - A Newsies::List instance to filter to.
    #
    # Returns a Hash mapping user_id to Subscription objects.
    private_class_method def self.fetch_subscriptions_for_users(user_ids, for_list:)
      scope = for_users(user_ids).for_list(for_list)

      scope.includes(:list).each_with_object({}) do |list_subscription, hash|
        newsies_list = Newsies::List.new(list_subscription.list_type, list_subscription.list_id)
        subscription = Subscription.new(newsies_list, nil, true, list_subscription.ignored, nil, list_subscription.created_at)
        subscription.list_object = list_subscription.list
        hash[list_subscription.user_id] = subscription
      end
    end

    # Private: Fetches subscriptions for a user with support for both page-based
    # and cursor-based pagination.
    #
    # user_id          - An Integer user id.
    # list_type        - Optional String that matches the list_id's type.
    # set              - Optional value to specify the set of subscriptions:
    #                    :all        - All subscriptions and ignores (default).
    #                    :subscribed - All subscriptions.
    #                    :ignored    - All ignores.
    # excluding        - An optional Array of Newsies::List instances to exclude.
    # for_lists        - An optional Array of Newsies::List instances to filter to.
    # page             - An optional Integer for which page to return (page-based pagination).
    # per_page         - An optional Integer for how many results to return per page.
    # sort             - An optional String or Symbol direction to sort (:asc, "asc", :desc, "desc").
    # cursor           - An optional Integer value that corresponds to a list_id (cursor-based pagination).
    # cursor_direction - One of :upwards or :downwards for cursor-based pagination.
    # limit            - An optional Integer number of results to return (cursor-based pagination).
    #
    # Returns an Array of Subscription objects.
    private_class_method def self.fetch_subscriptions(user_id, list_type: nil, set: nil, excluding: nil, for_lists: nil, page: nil, per_page: nil, sort: nil, cursor: nil, cursor_direction: nil, limit: nil)
      scope = for_user(user_id)
      scope = scope.where(list_type: list_type) if list_type
      scope = scope.for_lists(for_lists) if for_lists.present?

      case set
      when :subscribed
        scope = scope.excluding_ignored
      when :ignored
        scope = scope.only_ignored
      when nil, :all
        # no filtering
      else
        raise ArgumentError, "Invalid set option: #{set.inspect}"
      end

      scope = scope.excluding_lists(excluding) if excluding.present?

      # Cursor-based pagination: when cursor_direction is specified OR when limit is specified without page
      if cursor_direction || (limit && !page)
        case cursor_direction
        when :upwards
          scope = scope.where("list_id > ?", cursor) if cursor
          scope = scope.order(list_id: :asc)
        when :downwards
          scope = scope.where("list_id < ?", cursor) if cursor
          scope = scope.order(list_id: :desc)
        else
          scope = scope.order(list_id: :asc)
        end
        scope = scope.limit(limit) if limit

        results = scope.as_subscriptions
        results.reverse! if cursor_direction == :downwards
        results
      # Page-based pagination
      else
        case sort
        when "created_at:asc"
          scope = scope.order(created_at: :asc)
        when *VALID_SORT
          scope = scope.order(id: sort.to_sym)
        when nil
          if page
            # backwards compatibility for previous api which did not allow
            # choosing sort, but forced a sort as soon as page was not nil
            scope = scope.order(id: :desc)
          end
        else
          raise ArgumentError, "Invalid sort option: #{sort} (valid: #{VALID_SORT.to_sentence})"
        end

        if page
          per_page ||= DEFAULT_PAGE_SIZE
          scope = scope.offset((page - 1) * per_page).limit(per_page)
        end

        scope.as_subscriptions
      end
    end
  end
end
