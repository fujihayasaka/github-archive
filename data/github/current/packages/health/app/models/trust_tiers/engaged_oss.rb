# typed: true
# frozen_string_literal: true

require "set"

module TrustTiers
  class EngagedOss

    ENGAGED_OSS_REPOS_KEY = "trust_tiers:engaged_oss:repositories"

    TOP = 1000
    FLOOR = 100
    VISIBILITY = "public"
    ARCHIVED = false
    IS_FORK = false
    CREATED_BEFORE = 1.month
    MIN_STARS = 500
    MIN_FORKS = 25
    PUSHED_TO_AFTER = 1.year
    TOP_DECREMENT = 50

    # rubocop:disable Style/WordArray
    LANGUAGES = %w[
      JavaScript
      Python
      Java
      Go
      C++
      Ruby
      TypeScript
      PHP
      C#
      C
      Scala
      Shell
      Dart
      Rust
      Kotlin
      Swift
      Groovy
      Objective-C
      Elixir
      DM
      Perl
      CoffeeScript
      Lua
      PowerShell
      Clojure
      TSQL
      OCaml
      Vim\ script
      Haskell
      Erlang
      R
      Julia
      MATLAB
      Fortran
      F#
    ]
    # rubocop:enable Style/WordArray

    def self.populate
      repos_array = get_repos
      GitHub.dogstats.increment(
        "trust_tiers.engaged_oss.populate",
        tags: ["engaged_oss_found:#{repos_array.size}"]
      )
      populate_repos(repos_array)
    end

    def self.get_repos(query_phrase = "is:#{VISIBILITY} archived:#{ARCHIVED} fork:#{IS_FORK}
                      created:<#{ago_formatted(CREATED_BEFORE)} stars:>=#{MIN_STARS} forks:>=#{MIN_FORKS}
                      pushed:>#{ago_formatted(PUSHED_TO_AFTER)}")
      search_top = TOP

      # Get the overall top 1000
      repo_set = EngagedOssSearch.search(query_phrase, search_top).to_set

      # Get the top 1000, 950, 900, etc., going down the list of languages
      LANGUAGES.each do |language|
        lang_query_phrase = "language:#{language} #{query_phrase}"
        lang_top = [search_top, FLOOR].max
        repo_set.merge(EngagedOssSearch.search(lang_query_phrase, lang_top))
        search_top -= TOP_DECREMENT
      end

      repo_set.to_a
    end

    def self.populate_repos(repos_array)
      repos_array.each do |repo|
        populate_repo(repo)
      end
    end

    def self.populate_repo(repo)
      repo_key = key_for_repo(repo[:database_id])
      expiration_date = 10.days.from_now.utc

      Spam::Kv.store.set(repo_key, "true", expires: expiration_date)

      GitHub.logger.info(
        "code.namespace" => self.class.name,
        "code.function" => __method__.to_s,
        "gh.repo.id" => repo[:database_id],
        "gh.repo.nwo" => repo[:nwo],
        "repo_key" => repo_key,
        "expiration_date" => expiration_date
      )

      GitHub.dogstats.increment("trust_tiers.engaged_oss.populate_repo")
    end

    def self.is_repo_engaged_oss?(database_id)
      begin
        Spam::Kv.store.exists(key_for_repo(database_id)).value { false }
      rescue GitHub::KV::UnavailableError, GitHub::KV::MissingConnectionError => e
        # Log and fetch from the file system if KV is unavailable
        Failbot.report(e)
        is_repo_engaged_oss_from_file?(database_id)
      end
    end

    def self.key_for_repo(database_id)
      "#{ENGAGED_OSS_REPOS_KEY}:#{database_id}"
    end

    def self.ago_formatted(time)
      time.ago.strftime("%Y-%m-%d")
    end

    def self.is_repo_engaged_oss_from_file?(database_id)
      engaged_oss_from_file.include? database_id
    end

    # We load the file and use memoization to avoid reading the file every time
    def self.engaged_oss_from_file
      filename = "packages/health/app/models/trust_tiers/persisted_engaged_oss.json"
      @engaged_oss_from_file ||= begin
        repos = JSON.parse(File.read(filename))
        repos.to_set
      end
    end

    private_class_method :key_for_repo, :ago_formatted, :is_repo_engaged_oss_from_file?, :engaged_oss_from_file
  end
end
