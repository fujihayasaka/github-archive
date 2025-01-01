# typed: strict
# frozen_string_literal: true

module Copilot
  module ContentExclusion
    module RulesResolver
      extend T::Helpers

      include GitHub::Memoizer

      requires_ancestor { Copilot::ContentExclusionConfiguration }

      # This function will return you a list of paths that are relevent to a repository clone git clone url.
      # @see https://www.git-scm.com/docs/git-clone#_git_urls
      #
      # We also handle things like "git@github.com:monalisa/smile" for a rule of "smile"
      #
      # @param repo_url [String] The URL to find rules for.
      # @return [Array[String]] An array of path strings relevent to this repo string.
      sig { params(repo_url: String, url_normalizer: Copilot::ContentExclusion::UrlNormalizer).returns(T::Array[Copilot::ContentExclusion::Rule]) }
      def resolve_rules_for_repo_url(repo_url, url_normalizer = Copilot::ContentExclusion::UrlNormalizer.new)
        GitHub.dogstats.distribution_time("copilot.content_exclusion.resolve_rules_for_repo_url.duration") do
          return get_rules(repo_url, url_normalizer) if GitHub.review_lab?

          start = GitHub::Dogstats.monotonic_time
          cached_value = Copilot.redis.get(rules_resolver_cache_key(repo_url))
          result = T.let([], T::Array[Copilot::ContentExclusion::Rule])

          if cached_value.nil?
            result = get_rules(repo_url, url_normalizer)
          else
            result = JSON.parse(cached_value).map { |rule| Copilot::ContentExclusion::Rule.from_hash(rule) }
          end

          GitHub.dogstats.timing_since("copilot.ignore.rules_resolver.cache_time", start, tags: ["type:#{cached_value.nil? ? "miss" : "hit"}"])

          result
        rescue JSON::ParserError => error
          GitHub.logger.error("Failed to parse cached rules for document and url: #{rules_resolver_cache_key(repo_url)}", error:)
          Copilot.redis.del(rules_resolver_cache_key(repo_url))
          get_rules(repo_url, url_normalizer)
        rescue StandardError => error # rubocop:disable Lint/GenericRescue
          GitHub.logger.error("Failed to get rules for document and url: #{rules_resolver_cache_key(repo_url)}", error:)
          get_rules(repo_url, url_normalizer, set_cache: false)
        end
      end

      sig { returns(T::Array[Copilot::ContentExclusion::Rule]) }
      memoize def resolve_rules_for_all_files_scope
        return [] if resource.is_a?(::Repository)
        parsed_document&.all_scoped_rules || []
      end

      private

      sig { params(repo_url: String, url_normalizer: Copilot::ContentExclusion::UrlNormalizer, set_cache: T::Boolean).returns(T::Array[Copilot::ContentExclusion::Rule]) }
      def get_rules(repo_url, url_normalizer, set_cache: true)
        result = if !supported_repo_url?(repo_url, url_normalizer) || rules.empty?
          []
        else
          candidate_rules_for(repo_url, url_normalizer)
        end

        Copilot.redis.set(rules_resolver_cache_key(repo_url), result.to_json) if set_cache

        result
      end

      sig { params(repo_url: String).returns(String) }
      def rules_resolver_cache_key(repo_url)
        [
          "copilot:ignore:rules_resolver",
          Digest::SHA256.hexdigest(resource_type),
          Digest::SHA256.hexdigest(resource_id.to_s),
          Digest::SHA256.hexdigest(parsed_document&.document.to_s),
          Digest::SHA256.hexdigest(repo_url),
        ].join(":")
      end

      # This method filters the rulesets based on the repository URL and returns all matching paths.
      #
      # - If a ruleset's repository is `nil` or matches the repository URL or is a wildcard ("*"), all its paths are included.
      # - If the repository URL is just a GitHub name, it's prefixed with the current organization's name before comparison.
      # - If none of the above conditions are met, the method checks if the repository URL is equivalent through normalization.
      #
      # @param repo_url [String] The repository URL to match against the rulesets.
      # @return [Array<String>] An array of paths from the matching rulesets.
      sig { params(repo_url: String, url_normalizer: Copilot::ContentExclusion::UrlNormalizer).returns(T::Array[Copilot::ContentExclusion::Rule]) }
      def candidate_rules_for(repo_url, url_normalizer)
        if resource.nil?
          GitHub.logger.warn("No resource provided to resolve paths for", {
              "code.namespace": self.class.name, "code.function": __method__,
              "gh.copilot.ignore.id": id,
              "gh.copilot.ignore.has_organization": organization.present?,
              "gh.copilot.ignore.resource_id": resource_id,
              "gh.copilot.ignore.resource_type": resource_type,
          })
          return []
        end

        if resource.is_a?(::Repository)
          return rules if url_normalizer.match?(resource.ssh_url_for_api, repo_url)
          return []
        end

        org = T.let(resource, ::Organization) if resource.is_a?(::Organization)

        # Lets walk the rulesets and perform the filtering logic
        rules.select do |rule|
          pattern = rule.scope
          # not that we'll ever end up here, but if a repo is nil — include all its paths
          # If the scope is wildcard, include all wildcard paths and nothing else
          # Short circuit, if they are equal simply say yes let's include it
          next true if pattern.nil? || rule.is_all_scoped? || pattern == repo_url

          # What if the needle is "smile", for "monalisa/smile" — we need to prefix this with the current orgs name.
          # We check through checking that the url doesnt include <something>:// _or_ @<stuff>:
          # Skip this step if we're iterating through a business's rules, since they can't directly own organizations
          if ContentExclusion::GITHUB_OWNER_AND_OR_REPO_NAME_VALID_REGEX.match?(pattern)
            # If the pattern is a valid org/repo name, we don't need to prefix the org name
            if pattern.include?("/")
              pattern = github_repo_url(pattern)
            elsif org.present?
              pattern = github_repo_url("#{org.login_for_api}/#{pattern}")
            end
          end

          next url_normalizer.match?(pattern, repo_url)
        end
      end

      sig { params(path: String).returns(String) }
      def github_repo_url(path)
        "ssh://git@#{Rails.env.development? ? "localhost" : GitHub.host_name}/#{path}.git/"
      end

      sig { params(repo_url: String, url_normalizer: Copilot::ContentExclusion::UrlNormalizer).returns(T::Boolean) }
      def supported_repo_url?(repo_url, url_normalizer)
        result = url_normalizer.normalize(repo_url).ok?
        GitHub.dogstats.increment("gh.copilot.ignore.is_supported_repo_url.count", tags: ["result:#{result}"])
        result
      end

      sig { returns(T::Array[Copilot::ContentExclusion::Rule]) }
      memoize def rules
        parsed_document&.rules || []
      end
    end
  end
end
