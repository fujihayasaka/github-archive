# typed: false
# frozen_string_literal: true

# Spam::SearchRepo.new(:keywords => ['foo', 'bar]).find_spammers

# returns
# => ["DamianSiniakowicz", "xiaob", "balagurubaran", ..., "ryan864ptwzblog"]

# ["http www in:name", "services firm", "buy .com", "buy gold", "beauty", "diamonds", "diabetes", "anti aging", "skin care", "manufacture", "cambogia", "forskolin", "garcinia", "gojipro", "gmax", "acne", "handbag", "supplement", "adultsex", "adulttoys", "apnea", "bargain", "construction", "dentist", "fitness", "flooring", "forex", "galaxys4", "handbags", "hottubs", "jerseys", "leading", "lending", "lightbulbs", "realestate", "resale", "reviews", "roofer", "secrets", "sextoy", "shipping", "sleepapnea", "smarttv", "tahoe", "teethwhite", "termite", "trading", "treatment", "wedding"]
# ["diabetes", "anti aging", "skin care", "manufacture", "apnea", "bargain", "construction", "dentist", "fitness", "flooring", "forex", "galaxys4", "handbags", "hottubs", "resale", "reviews", "secrets", "sleepapnea", "smarttv", "tahoe", "trading"]
# ["cambogia", "forskolin", "garcinia", "gojipro", "gmax", "acne", "handbag", "supplement", "adultsex", "adulttoys", "jerseys", "leading", "lending", "lightbulbs", "realestate", "roofer", "sextoy", "shipping", "teethwhite", "termite", "treatment"]

module Spam
  class SearchRepo
    attr_accessor :keywords, :max_age, :per_query

    def initialize(options = {})
      options = options.reverse_merge({ max_age: 7.days.ago, per_query: 30 })
      @keywords = Array(options[:keywords]).reject { |t| t.blank? }
      @max_age = options[:max_age]
      @per_query = options[:per_query].to_i
      raise "Pointless without keywords" unless keywords.present?
    end

    # Build a repo search query that finds repositories which match a
    # keyword and are no older than max_age

    def build_query(keyword, page = 1)
      phrase = keyword + " created:>=" + max_age.strftime("%Y-%m-%d")
      Search::Queries::RepoQuery.new(phrase: phrase, page: page, per_page: 100)
    end

    # Finds a list of owners of repositories which are not older that max_age
    # and match a list of keywords. Repositories are found using repo search
    # using best match sort. After all results are fetched for a specific
    # keyword, only the last number_of_spammers_per_query are used to
    # construct the output list of users.

    def find_spammers
      spammers = []

      keywords.each do |keyword|
        collect = true
        page = 1
        hits = []

        while collect
          results = build_query(keyword, page).execute
          hits << results.results

          if results.next_page.present?
            page = results.next_page
          else
            collect = false
          end
        end

        # Heuristics to help reduce false positives:
        #   * filter out repositories that have a primary language
        #   * filter out repositories that don't have a description
        #   * filter out repositories owned by whitelisted users

        results = hits.flatten.select { |result| result["_model"].primary_language_name.nil? }
        results = results.select { |result| !result["_model"].description.blank? }
        results = results.select { |result| !result["_model"].owner.hammy? }
        spammers << results.last(per_query).map { |result| result["_model"].owner.login }
      end

      spammers.flatten.uniq
    end
  end
end
