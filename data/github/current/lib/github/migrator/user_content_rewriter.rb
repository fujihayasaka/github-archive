# typed: false
# frozen_string_literal: true

module GitHub
  class Migrator
    class UserContentRewriter
      CACHE_READ_BATCH_SIZE = 500.freeze

      def initialize(options = nil)
        options = options || {}
        @current_migration = options.fetch(:current_migration)
        @cache             = options[:cache] || Cache.new(URL_LOOKUP_CACHE_SIZE)
        @repo_source_urls  = []
      end

      # Public: Rewrite user content by updating urls and mentions for data
      # being migrated.
      #
      # model - Model instance that responds to #body and #attachments.
      #
      # Returns a String.
      def process(model)
        content = model.body
        return if content.nil?
        warm_cache
        content = content.dup

        # Rewrite repo urls first.
        repo_source_urls.each do |repo_source_url|
          replace = []
          escaped_repo_source_url = Regexp.escape(repo_source_url)
          regexp  = /(#{escaped_repo_source_url}\S+)\b/

          content.scan(regexp) do |url|
            url = url.first

            case url
            when /#{escaped_repo_source_url}\/(issues|pull|milestones|files)\/.+\z/
              if target_url = lookup(url)
                replace << [url, target_url]
              end
            when /#(?:commitcomment-|issuecomment-|event-|r)\d+\z/
              if target_url = lookup(url)
                replace << [url, target_url]
              end
            when /#{escaped_repo_source_url}\/(compare|tree|blob|commit)\//
              if target_url = lookup(repo_source_url)
                replace << [url, url.sub(repo_source_url, target_url)]
              end
            end
          end

          replace.each do |pair|
            content.sub!(pair[0], pair[1])
          end
        end

        # Rewrite mentions second.
        replace = {}
        content.scan(MENTION_REGEX) do |mention|
          source_url = if mention[1]
            "#{base_source_url}/orgs/#{mention[0]}/teams/#{mention[1]}"
          else
            "#{base_source_url}/#{mention[0]}"
          end

          if target_url = lookup(source_url)
            uri   = URI.parse(target_url)
            parts = uri.path.split("/")[1..-1]

            migrated_mention = if parts[0] == "orgs" && parts[2] == "teams"
              "#{parts[1]}/#{parts[3]}"
            else
              parts[0]
            end
            mention = mention.compact.join("/")

            replace["@#{mention}"] = "@#{migrated_mention}"
          else
            mention = mention.compact.join("/")
            replace["@#{mention}"] = "@#{mention}"
          end
        end
        content.gsub!(MENTION_REGEX, replace)

        # Rewrite asset urls.
        model.attachments.each do |attachment|
          if migratable_resource = current_migration.by_model(attachment)
            extension = File.extname(migratable_resource.source_url)
            filename_without_extension = File.basename(migratable_resource.source_url, extension)
            source_url_regex = /(https?:\/\/\S+)?\/\S+#{Regexp.escape(filename_without_extension)}(#{Regexp.escape(extension)})?/

            content.gsub!(source_url_regex, migratable_resource.target_url)
          end
        end

        content
      end

      private

      # Internal: MigratableResource scope for this migration.
      #
      # Returns an ActiveRecord scope.
      attr_reader :current_migration

      # Internal: LRU Cache used for source_url to target_url lookups.
      #
      # Returns a GitHub::Migrator::Cache.
      attr_reader :cache

      # Internal: Array of source_url strings for the repositories in this
      # migration.
      #
      # Returns an Array.
      attr_reader :repo_source_urls

      # Internal: Maximum number of records to store in the cache.
      #
      # Returns an Integer.
      URL_LOOKUP_CACHE_SIZE = 10_000

      # Internal: Regexp used to find and replace user and team @mentions.
      MENTION_REGEX = /@([\w\-]+)(?:\/([\w\-]+)+)?/

      # Internal: Get the base source url for this migration.
      #
      # Returns a String.
      def base_source_url
        @base_source_url ||= begin
          uri = URI.parse(repo_source_urls.first)
          "#{uri.scheme}://#{uri.hostname}"
        end
      end

      # Internal: Lookup the source_url and cache the result.
      #
      # source_url - String url.
      #
      # Returns a String or NilClass.
      def lookup(source_url)
        cache.getset(source_url) do
          current_migration.by_source_url(source_url).try(:target_url)
        end
      end

      # Internal: Warm the source_url to target_url lookup cache.
      def warm_cache
        @warm_cache ||= begin
          offset = 0
          loop do
            migratable_resources = MigratableResource.throttle_with_retry(max_retry_count: 4) do
              current_migration
                .by_model_type(MigratableModels.cache_url_lookup_models)
                .limit(CACHE_READ_BATCH_SIZE)
                .offset(offset)
            end

            break if migratable_resources.none?

            migratable_resources.each do |migratable_resource|
              cache.getset(migratable_resource.source_url) do
                migratable_resource.target_url
              end

              if migratable_resource.model_type == "repository"
                @repo_source_urls << migratable_resource.source_url
              end
            end

            offset += CACHE_READ_BATCH_SIZE
          end

          true
        end
      end
    end
  end
end
