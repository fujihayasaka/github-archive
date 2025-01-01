# typed: true
# frozen_string_literal: true

class Contribution::Accessor
  include Scientist

  def self.clear_cache_for_user(user)
    Cache.clear_cache_for_user(user)
  end

  def self.bulk_clear_cache_for_users(user)
    Cache.bulk_clear_cache_for_users(user)
  end

  # user - The user to look at contributions for
  # viewer - The viewer viewing the contributions
  # date_range - The date range to filter on
  # organization_id - ID of an organization to limit contributions to (nil => all)
  # skip_restricted - Whether to skip restricted contributions altogether
  # excluded_organization_ids - Filter out contributions associated with these org IDs
  def initialize(
    user:,
    viewer:,
    contribution_classes:,
    date_range:,
    organization_id:,
    skip_restricted:,
    excluded_organization_ids: [],
    lightweight: false,
    use_contribution_fetchers: false
  )
    @user = user
    @viewer = viewer
    @contribution_classes = contribution_classes
    @date_range = date_range
    @organization_id = organization_id
    @skip_restricted = skip_restricted
    @excluded_organization_ids = excluded_organization_ids || []
    @lightweight = lightweight

    @fetchers = {}
    if use_contribution_fetchers
      contribution_classes.each do |contribution_class|
        if fetcher_class = contribution_class.fetcher_class
          @fetchers[contribution_class] = fetcher_class.new(
            user: @user,
            date_range: @date_range,
            organization_id: @organization_id,
            excluded_organization_ids: @excluded_organization_ids,
            lightweight: @lightweight
          )
        end
      end
    end
  end

  # Public: Returns whether any contributions exist of the given type that were
  # contributed earlier than the given subject.
  #
  # contribution_class - The contribution type to check.
  # subject - The subject to check against.
  #
  # Returns a boolean.
  def any_contribution_before?(contribution_class, subject)
    if fetcher = @fetchers[contribution_class]
      fetcher.any_contribution_before?(subject)
    else
      first_contribution = load_first(contribution_class)
      first_contribution.present? && first_contribution.created_before?(subject)
    end
  end

  # Public: Returns the first contribution of the given type respecting the
  # time range. Might return nil in case the viewer cannot access
  # the first contribution or it did not happen within the time range.
  #
  # contribution_class - Contribution type.
  #
  # Returns Contribution, or nil
  def load_first(contribution_class)
    contribution = fetch_first_contribution_of(contribution_class)

    if contribution && @date_range.cover?(contribution.occurred_at.to_date)
      assign_visibility_and_filter([contribution]).first
    end
  end

  # Public: The counts of visible contributions broken down by repository_id
  #
  # Returns Hash[Integer] => Integer
  def visible_counts_by_repository_id
    load_cached_contributions unless defined?(@visible_counts_by_repository_id)
    fetch_all_contributions unless defined?(@visible_counts_by_repository_id)

    @visible_counts_by_repository_id
  end

  # Public: Returns contributions broken down by class
  #
  # Returns Hash[Class] => Integer
  def counts_by_class_name
    load_cached_contributions unless defined?(@counts_by_class_name)
    fetch_all_contributions unless defined?(@counts_by_class_name)

    @counts_by_class_name
  end

  # Public: Returns contribution counts grouped by day
  #
  # Returns: Hash[Date] => Integer
  def counts_by_day
    load_cached_contributions unless defined?(@counts_by_day)
    fetch_all_contributions unless defined?(@counts_by_day)

    @counts_by_day
  end

  # Public: Returns a count of the restricted contributions in this period
  #
  # Returns: Integer
  def restricted_contributions_count
    fetch_all_contributions

    @restricted_contributions_count
  end

  # Public: The first visible contribution of a given type
  #
  # Returns Contribution, nil
  def first_visible_contribution(contribution_class)
    fetch_all_contributions

    @first_visible_contribution[contribution_class]
  end

  # Public: Returns contributions of the specified type the viewer can access.
  #
  # Returns: Array of Contribution objects.
  def visible_contributions_of(contribution_class)
    fetch_all_contributions

    @visible_contributions[contribution_class]
  end

  # Public: Returns the earliest restricted contribution date
  #
  # Returns: Date
  def earliest_restricted_contribution_date
    fetch_all_contributions

    @restricted_contribution_dates.first
  end

  # Public: Returns the most recent restricted contribution date
  #
  # Returns: Date
  def latest_restricted_contribution_date
    fetch_all_contributions

    @restricted_contribution_dates.to_a.last
  end

  private

  # Private: Uses GitHub.cache to populate convenience cache ivars. If an ivar is not set after calling this, there was no cached data for that ivar
  def load_cached_contributions
    # Don't bother checking the cache if the user's profile should be private
    if @user.private_profile_for?(@viewer)
      initialize_convenience_caches
      return
    end

    if cached_data = cache.get
      GitHub.dogstats.increment("contributions.accessor.cache.hit")

      if visible_counts_by_repository_id = cached_data[:visible_counts_by_repository_id]
        @visible_counts_by_repository_id = visible_counts_by_repository_id
        sanitize_visible_counts_by_repository_id
      end

      if counts_by_day = cached_data[:counts_by_day]
        @counts_by_day = counts_by_day
      end

      if counts_by_class_name = cached_data[:counts_by_class_name]
        @counts_by_class_name = counts_by_class_name
      end
    end
  end

  # Private: Sanitizes @visible_counts_by_repository_id by passing repository ids
  # through VisibilityChecker. This method should be used when pulling back
  # count data from a cache.
  def sanitize_visible_counts_by_repository_id
    visibility_checker = Contribution::VisibilityChecker.new(
      user: @user,
      viewer: @viewer,
      subject_map: { "Repository" => @visible_counts_by_repository_id.keys },
    )

    valid_repository_ids = visibility_checker.valid_repository_ids(
      repository_ids: @visible_counts_by_repository_id.keys,
      skip_restricted: true,
    )

    @visible_counts_by_repository_id.slice!(*valid_repository_ids)
  end

  # Private: Fetches all contributions
  def fetch_all_contributions
    # Don't load anything if the user's profile should be private
    if @user.private_profile_for?(@viewer)
      initialize_convenience_caches
      @loaded = true
    end

    return if @loaded

    initialize_convenience_caches

    return if @user.large_bot_account?

    GitHub.dogstats.increment("contributions.accessor.cache.miss")

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    tags = ["excluding_orgs:#{@excluded_organization_ids.any?}"]
    GitHub.dogstats.distribution_time("contributions.accessor.load", tags: tags) do
      contributions = @contribution_classes.flat_map do |contribution_class|
        fetch_contributions_for(contribution_class)
      end

      contributions = assign_visibility_and_filter(contributions)

      contributions.each do |contribution|
        update_convenience_caches_with(contribution)
      end
    end

    set_all_caches

    GitHub.dogstats.distribution(
      "contributions.accessor.dist.time",
      GitHub::Dogstats.duration(start),
    )

    @loaded = true
  end

  # Private: Fetches all contributions of the given class in the time range
  #
  # Returns Array[contribution_class]
  def fetch_contributions_for(contribution_class)
    stat_key = "contributions.fetch.#{contribution_class.name.demodulize.underscore}"
    GitHub.dogstats.distribution_time(stat_key) do
      ActiveRecord::Base.connected_to(role: :reading) do
        if fetcher = @fetchers[contribution_class]
          records = fetcher.subjects_in_date_range
        else
          records = contribution_class.subjects_for(
            @user,
            date_range: @date_range,
            organization_id: @organization_id,
            excluded_organization_ids: @excluded_organization_ids,
            lightweight: @lightweight
          )
        end

        contributions = records.map { |subject| contribution_class.new(user: @user, subject: subject) } # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        if contribution_class.needs_filtering_by_occurred_at?
          contributions.select! { |contribution| @date_range.cover?(contribution.occurred_at.to_date) }
        end

        contributions.sort.reverse
      end
    end
  end

  # Private: Fetches the first ever contribution of the given class.
  #
  # Returns Contribution or nil
  def fetch_first_contribution_of(contribution_class)
    ActiveRecord::Base.connected_to(role: :reading) do
      subject = if fetcher = @fetchers[contribution_class]
        fetcher.first_subject
      else
        contribution_class.first_subject_for(@user, excluded_organization_ids: @excluded_organization_ids)
      end

      contribution_class.new(user: @user, subject: subject) if subject
    end
  end

  # Private: Initialize the blank state of the convenience caches
  def initialize_convenience_caches
    @counts_by_class_name = Hash.new(0)
    @counts_by_day = Hash.new(0)
    @restricted_contribution_dates = []
    @restricted_contributions_count = 0
    @visible_contributions = Hash.new { |h, k| h[k] = [] }
    @visible_counts_by_repository_id = Hash.new(0)
    @first_visible_contribution = {}
  end

  # Private: Add the contribution to the various instance variables
  def update_convenience_caches_with(contribution)
    @counts_by_class_name[contribution.contribution_class.name] += contribution.contributions_count
    @counts_by_day[contribution.occurred_on] += contribution.contributions_count

    if contribution.restricted?
      @restricted_contribution_dates << contribution.occurred_on
      @restricted_contribution_dates = @restricted_contribution_dates.uniq.sort
      @restricted_contributions_count += contribution.contributions_count
    else
      @visible_contributions[contribution.contribution_class] << contribution

      repository_id = contribution.repository_id
      @visible_counts_by_repository_id[repository_id] += contribution.contributions_count if repository_id

      earliest_at = @first_visible_contribution[contribution.contribution_class]&.occurred_at
      @first_visible_contribution[contribution.contribution_class] = contribution if earliest_at.nil? || contribution.occurred_at < earliest_at
    end
  end

  # Private: Remove invalid contributions, and replace contributons which should not have
  # their details visible to the viewer (restricted) with RestrictedContribution objects
  #
  # Returns Array[Contribution]
  def assign_visibility_and_filter(contributions)
    subject_map = contributions.each_with_object(Hash.new { |h, k| h[k] = [] }) do |contrib, m|
      m[contrib.associated_subject.class.to_s] << contrib.associated_subject.id if contrib.associated_subject
    end
    visibility_checker = Contribution::VisibilityChecker.new(user: @user, viewer: @viewer, subject_map: subject_map)

    contributions.each.with_object([]) do |contribution, keepers|
      if contribution.associated_subject.nil?
        keepers << Contribution::RestrictedContribution.new(contribution) unless @skip_restricted
        next
      end

      next unless visibility_checker.valid?(contribution.associated_subject.class.to_s, contribution.associated_subject.id)
      next if pull_request_user_spammy?(contribution)
      next unless contribution_matches_org?(contribution)

      if visibility_checker.restricted?(contribution.associated_subject.class.to_s, contribution.associated_subject.id)
        unless @skip_restricted
          keepers << Contribution::RestrictedContribution.new(contribution)
        end
      else
        keepers << contribution
      end
    end
  end

  def contribution_matches_org?(contribution)
    return true if @organization_id.nil?

    contribution.organization_id == @organization_id
  end

  def set_all_caches
    cache.set(
      visible_counts_by_repository_id: @visible_counts_by_repository_id,
      counts_by_day: @counts_by_day,
      counts_by_class_name: @counts_by_class_name,
    )
  end

  # Private: Returns a cache that invalidates any of the following changes:
  #   - mass-invalided by bumping the CACHE_VERSION
  #   - invalidated in stafftools (see: user_namespace)
  #   - date range
  #   - contribution classes
  #   - viewer_id
  #   - org is specified
  #   - excluded_organization_ids is specified
  #   - lightweight is specified
  def cache
    return @cache if defined? @cache

    @cache = Cache.new(
      user: @user,
      viewer: @viewer,
      contribution_classes: @contribution_classes,
      date_range: @date_range,
      organization_id: @organization_id,
      skip_restricted: @skip_restricted,
      excluded_organization_ids: @excluded_organization_ids,
      lightweight: @lightweight,
    )
  end

  def pull_request_user_spammy?(contribution)
    # We don't generally check for spammy contributions on the profile page.
    # This generally works out fine because if the user is spammy whose profile
    # you try to view:
    #   - If you're not a site admin, we 404 so you don't load any of the
    #   spammer's contributions anyway
    #   - If you _are_ a site admin, we show you the spammer's profile and all
    #   of their contributions
    #
    # And if the user whose profile you're viewing isn't spammy, but they've
    # contributed to a spammy _repo_, that's handled by VisibilityChecker
    # class, which filters out contributions to spammy repos.
    #
    # But we're left with a bit of an edge case where:
    #   A non-spammy submitted a PR review to a PR opened by a spammy user on a
    #   repo that isn't spammy See issue for an example:
    #   https://github.com/github/profile/issues/19
    #
    # This is why we're spam-checking here specifically for the hammy review on
    # a spammy PR case!
    contribution.is_a?(Contribution::CreatedPullRequestReview) &&
      contribution.pull_request&.hide_from_user?(@viewer)
  end
end
