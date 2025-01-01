# typed: false
# frozen_string_literal: true

module ActionsCacheControllerMethods
  include FeatureFlagHelper

  FILTER_FIELDS = [:branch, :key, :sort]
  DEFAULT_PER_PAGE = 25

  def cache_query
    params[:query] || ""
  end

  def cache_item_filters
    return @_cache_item_filters if defined?(@_cache_item_filters)
    query = cache_query
    parsed_query = Search::ParsedQuery.parse(query, terms: FILTER_FIELDS)
    filters_array = parsed_query.
      select { |param| param.is_a?(Array) }.
      map { |param| param.first(2) }
    filters = Hash[filters_array]

    @_cache_item_filters = filters
  end

  def delete_cache_by_id(id)
    response = ActionsCacheManagementHelper.delete_repo_cache_by_id(repo: current_repository, id:, current_user:)

    if response.call_succeeded?
      flash[:notice] = "Cache deleted successfully."
    else
      flash[:error] = "Failed to delete this cache."
    end
  end

  def cache_items
    branch = cache_item_filters[:branch].dup
    branch.prepend("refs/heads/") if branch.present? && !branch.start_with?("refs/")

    sort, direction = (cache_item_filters[:sort] || "accessed-desc").split("-")

    response = ActionsCacheManagementHelper.get_repo_caches(
      repo: current_repository,
      key: cache_item_filters[:key],
      ref: branch,
      sort: sort_labels[sort],
      direction:,
      page: current_page,
      per_page: DEFAULT_PER_PAGE,
    )

    paged_cache_items(response)
  end

  def paged_cache_items(response)
    if !response.call_succeeded?
      flash[:error] = "We are having problems in getting  actions cache. The results may not be complete."
      return { total_count: 0, actions_caches: [].paginate }
    end

    caches = WillPaginate::Collection.create(current_page, DEFAULT_PER_PAGE, response.value.total_caches) do |pager|
      pager.replace(response.value.caches.map { |cache| cache_hash(cache) })
    end

    {
      total_count:  response.value.total_caches,
      actions_caches: caches
    }
  end

  def cache_hash(cache)
    {
      id: cache.id,
      ref: cache.scope,
      key: cache.key,
      version: cache.version,
      last_accessed_at: Time.at(cache.lastAccessed.to_i),
      created_at: Time.at(cache.created.to_i),
      size_in_bytes: cache.size
    }
  end

  def sort_labels
    {
      "accessed" => "last_accessed_at",
      "created" => "created_at",
      "size" => "size_in_bytes",
    }
  end

  def cache_usage_stats
    repo_cache = ActionsCacheUsage.get_repo_cache_usage(current_repository)
    current_cache_size_in_gb = ((repo_cache&.active_caches_size.to_f) / (1024 * 1024 * 1024)).round(2)
    cache_limit = ActionsCacheUsagePolicy.get_repository_cache_usage_policy(current_repository: current_repository)
    {
      "cache_limit": cache_limit,
      "current_cache_size": current_cache_size_in_gb
    }
  end

  def cache_usage_above_warning_threshold?(cache_limit, current_cache_size)
    current_cache_size > 0.75 * cache_limit
  end
end
