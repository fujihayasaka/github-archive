# typed: false
# frozen_string_literal: true

class Trending
  BATCH_SIZE = 100
  LEADERBOARD_EXCLUSIONS = [
    1300192,   # octocat/spoon-knife
    1334369,   # resume/resume.github.com
    23082495,  # sebyddd/YouAreAwesome
    28457823,  # FreeCodeCamp/FreeCodeCamp
    32334018,  # letsgetrandy/DICSS
    41103286,  # lbryio/lbry
    135785971, # upend/IF_MS_BUYS_GITHUB_IMMA_OUT
    152327866, # Igglybuff/awesome-piracy
  ].freeze

  attr_reader :limit,
    :since,
    :period,
    :language_id,
    :avg_num_stars,
    :avg_num_stars_in_per,
    :avg_num_forks,
    :avg_num_follows_in_per,
    :fresh_repo_push_date,
    :min_repo_create_date

  def initialize(period:, limit: nil, language: nil, skip_min: false, from_job: false)
    case period
    when "monthly"
      @period = "monthly"
      @since = 1.month.ago
    when "weekly"
      @period = "weekly"
      @since = 1.week.ago
    else
      @period = "daily"
      @since = 1.day.ago
    end

    @language_id =
      if !language
        nil
      elsif language == "unknown"
        "unknown"
      elsif language_name = LanguageName.find_by_alias(language)
        language_name.id
      end

    @limit = limit || 25
    @skip_min = skip_min
    @from_job = from_job

    @avg_num_stars          = skip_min ? 0 : 20
    @avg_num_stars_in_per   = skip_min ? 0 : 5
    @avg_num_forks          = skip_min ? 0 : 4
    @avg_num_follows_in_per = skip_min ? 0 : 2
    @fresh_repo_push_date   = skip_min ? 7.years.ago : 7.days.ago
    @min_repo_create_date   = skip_min ? DateTime.now : 1.day.ago # to avoid spammers trying to game the top daily
  end

  def allow_slow_queries_from_jobs(&block)
    if @from_job
      ActiveRecord::Base.connected_to(role: :reading_slow, &block)
    else
      ActiveRecord::Base.connected_to(role: :reading, &block)
    end
  end

  def self.repo_ids(options)
    new(**options).repo_ids
  end

  def repo_ids
    trenders   = {}

    # this cache_key is used to show results in /explore page
    cache_key = "trending:repos:query:#{@period}"

    force_cache_enabled do
      # Collect the data and save it in this cache key
      trenders = GitHub.cache.fetch(cache_key) do
        t = {}
        t = forks_query(t)
        t = repos_stars_query(t)

        ActiveRecord::Base.connected_to(role: :writing) do
          # so we know how old the cache is
          Explore::Kv.store.set("#{cache_key}:time", DateTime.now.to_i.to_s)
        end
        t
      end
    end

    # limit by language
    trenders = limit_by_language(trenders)

    # sort the trenders
    trenders = sort_trenders(trenders).first(limit)

    repo_ids = trenders.map { |tr| tr[0] }
    repos = Repository.includes(:network_privilege).where(id: repo_ids).index_by(&:id)

    # repos could have been deleted since calculating the trenders
    trenders.reject! { |tr| repos[tr[0]].nil? }

    # there may be trending repos that we do not wish to highlight
    filter_trending_repos(trenders, repos)

    # backfill with backup repos if trenders isn't limit
    while trenders.length < limit
      backup_trenders = repos_backup(repo_ids)
      break if backup_trenders.empty?
      trenders = trenders + backup_trenders

      backup_repo_ids = backup_trenders.map { |tr| tr[0] }
      repo_ids += backup_repo_ids
      backup_repos = Repository.where(id: backup_repo_ids)
      break if backup_repos.empty?
      repos = repos.merge(backup_repos.index_by(&:id))

      filter_trending_repos(trenders, repos)
    end

    trenders.first(limit).map do |repo_id, val|
      [repo_id, val]
    end
  end

  # Filter out repos with inappropriate names or have been explicitly marked to be excluded in stafftools,
  # this is less about being complete and never having false negatives than catching obvious problems
  # before they're sent out as explore emails or highlighted on our /explore page (cf. #39752).
  def filter_trending_repos(trenders, repos)
    trenders.delete_if do |tr|
      repos[tr[0]].name =~ /\u0066uck/i || repos[tr[0]].async_is_hidden_from_discovery?.sync
    end
  end

  def self.repos(viewer: nil, cache_key: "", ttl:, options:)
    repo_includes = options.delete(:repo_includes)
    new(**options).repos(viewer, cache_key, ttl, repo_includes: repo_includes)
  end

  def repos(viewer, cache_key, ttl, repo_includes: false)
    trending_ids = GitHub.cache.fetch("#{cache_key}:ids", ttl: ttl) do
      repo_ids
    end

    includes  = [{ owner: :profile }, :mirror]
    includes  = includes | repo_includes if repo_includes
    block_ids = viewer ? viewer.ignored_users.pluck(:ignored_id) : []

    repos = Repository.where(active: true, id: trending_ids.map(&:first)).where.not(owner_id: block_ids).
                      includes(includes).index_by(&:id)
    trending_ids.map { |repo_id, val| [repos[repo_id], val] }.reject { |trend| trend[0].nil? }
  end

  def self.users(options)
    new(**options).users
  end

  def users
    trenders = fetch_trenders

    # skip db call if no trenders
    return [] if trenders.empty?

    # Map the users
    user_ids = trenders.map { |tr| tr[0] }

    users_by_id = User.where(id: user_ids, private_profile: false)
      .includes(:profile)
      .map { |user| [user.id, user] }
      .to_h

    users_and_scores = trenders.map do |uid, val|
      [users_by_id[uid], val]
    end

    users_and_scores.reject { |user_and_score| user_and_score[0].nil? }
  end

  private

  def fetch_trenders
    trenders = {}

    # this cache_key is used to show results in /explore page
    cache_key = "trending:users:query:#{@period}"

    # Collect the data
    force_cache_enabled do
      trenders = GitHub.cache.fetch(cache_key) do
        t = {}
        t = follows_query(t)
        t = users_stars_query(t)

        ActiveRecord::Base.connected_to(role: :writing) do
          # so we know how old the cache is
          Explore::Kv.store.set("#{cache_key}:time", DateTime.now.to_i.to_s)
        end
        t
      end
    end

    trenders = limit_by_language(trenders)

    # sort the trenders
    sort_trenders(trenders).first(limit)
  end

  # trenders - A list of trenders
  def limit_by_language(trenders)
    return trenders unless language_id
    trenders.delete_if do |_tr, val|
      if language_id == "unknown"
        val.has_key?(:languages) || (!val.has_key?(:stars) && !val.has_key?(:forks))
      else
        !val.has_key?(:languages) || !val[:languages].include?(language_id)
      end
    end
  end

  # trenders - A list of trenders
  def sort_trenders(trenders)
    trenders.sort_by do |_key, value|
      scores = [0]
      scores.push value[:follows][:score] if value.has_key?(:follows)
      scores.push value[:forks][:score] if value.has_key?(:forks)
      scores.push value[:stars][:score] if value.has_key?(:stars)
      scores.inject(:+)
    end.reverse
  end

  # when no repos were found, query the top repos of all time.
  #
  # not_repo_ids - an array of repo ids not to include in the results
  # limit - the number of top repos to return
  def repos_backup(not_repo_ids)
    trenders = []

    strings = []
    params = []

    # repo ids
    strings.push "id not in (?)" if not_repo_ids.length > 0
    params.push not_repo_ids if not_repo_ids.length > 0

    # language
    strings.push "primary_language_name_id = ?" if language_id
    params.push language_id if language_id

    repositories = Repository.public_scope.select(
      "id, #{Repository.stargazer_count_column}",
    ).order(
      "#{Repository.stargazer_count_column} desc",
    ).limit(limit).where(
      [strings.join(" && "), params].flatten(1),
    )

    repositories.group_by(&:id).each_key do |rid|
      trenders << [rid, {}]
    end

    trenders
  end

  def follows_query(trenders)
    followings = allow_slow_queries_from_jobs do
      GitHub.dogstats.distribution_time("trending.#{@period}.users.follows_query.sql") do
        Following.not_spammy.
          where(["followers.created_at > ?", @since]).
          group(:following_id).
          having("total >= ?", avg_num_follows_in_per).
          pluck(:following_id, Arel.sql("SUM(#{trending_score_sql(max: TrendingScorer::FOLLOW_MAX, min: TrendingScorer::FOLLOW_MIN, column: "created_at")}) AS score"), Arel.sql("COUNT(*) AS total"))
      end
    end

    followings.each do |(following_id, score, total)|
      trenders[following_id] ||= {}
      trenders[following_id][:follows] = {
        total: total,
        score: score,
      }
    end

    trenders
  end

  def users_stars_query(trenders)
    repository_data = allow_slow_queries_from_jobs do
      GitHub.dogstats.distribution_time("trending.#{@period}.repos.unjoined_stars_query.sql") do
        Repository.from("repositories USE INDEX(index_repositories_on_watcher_count_and_created_at_and_pushed_at)").
          public_scope.active.
          where("#{Repository.stargazer_count_column} > ?", avg_num_stars).
          where("pushed_at > ?", fresh_repo_push_date).
          where("created_at < ?", min_repo_create_date).
          where.not(id: LEADERBOARD_EXCLUSIONS).
          where(disabled_at: nil).
          pluck(:id, :owner_id, :primary_language_name_id)
      end
    end

    data_by_starrable_id = allow_slow_queries_from_jobs do
      GitHub.dogstats.distribution_time("trending.#{@period}.stars.unjoined_stars_query.sql") do
        Star.not_spammy.repositories.
          where("created_at > ?", @since).
          group(:starrable_id).
          pluck(:starrable_id, Arel.sql("SUM(#{trending_score_sql(max: TrendingScorer::STAR_MAX, min: TrendingScorer::STAR_MIN, column: "created_at")}) AS score"), Arel.sql("COUNT(*)")).
          map { |starrable_id, score, total| [starrable_id, { score: score, total: total }] }.to_h
      end
    end

    # Intermediate Hash that combines attributes from Repository and Star
    hash = Hash.new { |h, k| h[k] = { stars: { total: 0, score: 0.0 }, languages: Set.new } }

    repository_data.each do |repository_id, owner_id, primary_language_name_id|
      next unless data_by_starrable_id.key?(repository_id)

      data = data_by_starrable_id[repository_id]
      hash[owner_id][:stars][:score] += data[:score]
      hash[owner_id][:stars][:total] += data[:total]
      hash[owner_id][:languages] << primary_language_name_id if primary_language_name_id
    end

    # Update the input `trenders` hash with Star totals, scores, and languages
    hash.each do |owner_id, data|
      if data[:stars][:total] >= avg_num_stars_in_per
        trenders[owner_id] ||= {}
        trenders[owner_id][:stars] = data[:stars]
        trenders[owner_id][:languages] = data[:languages].to_a unless data[:languages].empty?
      end
    end

    trenders
  end

  def repos_stars_query(trenders)
    repository_data = allow_slow_queries_from_jobs do
      GitHub.dogstats.distribution_time("trending.#{@period}.repos.fast_repos_query.sql") do
        Repository.from("repositories USE INDEX(index_repositories_on_watcher_count_and_created_at_and_pushed_at)").
          public_scope.active.
          where("#{Repository.stargazer_count_column} > ?", avg_num_stars).
          where("pushed_at > ?", fresh_repo_push_date).
          where("created_at < ?", min_repo_create_date).
          where.not(id: LEADERBOARD_EXCLUSIONS).
          where(disabled_at: nil).
          pluck(:id, :primary_language_name_id)
      end
    end

    data_by_starrable_id = allow_slow_queries_from_jobs do
      GitHub.dogstats.distribution_time("trending.#{@period}.stars.unjoined_stars_query.sql") do
        Star.not_spammy.repositories.
          where("created_at > ?", @since).
          group(:starrable_id).
          pluck(:starrable_id, Arel.sql("SUM(#{trending_score_sql(max: TrendingScorer::STAR_MAX, min: TrendingScorer::STAR_MIN, column: "created_at")}) AS score"), Arel.sql("COUNT(*) AS total")).
          map { |starrable_id, score, total| [starrable_id, { score: score, total: total }] }.to_h
      end
    end

    total = 0

    repository_data.each do |repository_id, primary_language_name_id|
      next unless data_by_starrable_id.key?(repository_id)

      total += 1
      data = data_by_starrable_id[repository_id]

      if data[:total] >= avg_num_stars_in_per
        trenders[repository_id] ||= {}
        trenders[repository_id][:stars] = data.dup

        trenders[repository_id][:languages] = [primary_language_name_id] if primary_language_name_id
      elsif trenders[repository_id] && trenders[repository_id].has_key?(:forks)
        trenders.delete(repository_id)
      end
    end

    GitHub.dogstats.distribution("trending.#{@period}.repos.fast_repos_query.results", total)

    trenders
  end

  def forks_query(trenders)
    forks = allow_slow_queries_from_jobs do
      GitHub.dogstats.distribution_time("trending.#{@period}.repos.forks_query.sql") do
        Repository.public_scope.active.
          group("repositories.parent_id").
          joins(%Q(inner join repositories as repos2 on repositories.parent_id = repos2.id)).
          where(<<~SQL, @since, fresh_repo_push_date, avg_num_forks, avg_num_stars, min_repo_create_date).
            repositories.created_at > ? AND
            repositories.parent_id is not null AND
            repos2.pushed_at > ? AND
            repos2.public_fork_count > ? AND
            repos2.#{Repository.stargazer_count_column} > ? AND
            repos2.created_at < ?
          SQL
          pluck(Arel.sql("repositories.parent_id"), Arel.sql("repos2.primary_language_name_id"), Arel.sql("SUM(#{trending_score_sql(max: TrendingScorer::FORKS_MAX, min: TrendingScorer::FORKS_MIN, column: "repositories.created_at")}) AS score"), Arel.sql("COUNT(*) as total"))
      end
    end

    forks.each do |parent_id, primary_language_name_id, score, total|
      trenders[parent_id] ||= {}
      trenders[parent_id][:forks] = {
        total: total,
        score: score,
      }
      trenders[parent_id][:languages] = [primary_language_name_id] if primary_language_name_id
    end

    trenders
  end

  def trending_score_sql(min:, max:, column:)
    ActiveRecord::Base.sanitize_sql([<<~SQL, max: max, min: min, since: @since.to_date.to_datetime, now: DateTime.now])
      CAST(LEAST(:max,
        GREATEST(:min,
          (
            (
              TIMESTAMPDIFF(SECOND, :since, #{column})
              /
              TIMESTAMPDIFF(SECOND, :since, :now)
            ) * (:max - :min)
          ) + :min
        )
      ) AS DECIMAL(10, 3))
    SQL
  end

  def force_cache_enabled
    skipmc = GitHub.cache.skip

    # don't skip repos query cache, could take up to 40+ seconds
    GitHub.cache.skip = false unless GitHub.enterprise? || Rails.env.development?

    yield

  ensure
    GitHub.cache.skip = skipmc
  end
end
