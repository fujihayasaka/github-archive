# typed: false
# frozen_string_literal: true

module GitHub
  class Migrator
    module MigratorHelper
      include TarUtils
      include MigratableModels

      # Public: All MigratableResource records associated with this migration.
      #
      # Returns an ActiveRecord::Relation.
      def current_migration
        @current_migration ||= MigratableResource.for_guid(guid)
      end

      def target_url_for(source_url)
        cache.getset("target_url_for_source_url:#{source_url}") do
          current_migration.by_source_url(source_url)&.target_url
        end
      end

      private

      # Internal: Cleanup after the migrator.
      def cleanup_after_migrator
        FileUtils.rm_rf(migration_path, secure: true)

        # Forecully remove the archive staging dirctory if FileUtils wasn't able to nuke it
        if File.exist?(migration_path)
          options = ["-rf", "#{migration_path}"]

          child = Progeny::Command.new("rm", *options)
          raise GitHub::Migrator::CleanupArchiveError, "Unable to prune staging directory: #{child.err}" unless child.success?
        end
      end

      # Internal: LRU cache.
      #
      # Returns a Cache.
      def cache
        @cache ||= Cache.new(GitHub::Migrator::CACHE_SIZE)
      end

      # Internal: ModelUrlService handles url_for_model and model_for_url lookups.
      # It caches lookups to speed up migrations.
      #
      # Returns a ModelUrlService.
      def model_url_service
        @model_url_service ||= ModelUrlService.new(cache: cache)
      end
      delegate :url_for_model, :model_for_url, to: :model_url_service

      # Internal: Is the url invalid?
      #
      # url - String url.
      #
      # Returns a TrueClass or FalseClass.
      def url_invalid?(url)
        !model_url_service.url_valid?(url)
      end

      # Internal: Go into "importing" mode.
      #
      # * notifications are disabled
      # * content creation rate limits are disabled
      # * stratocaster is disabled
      # * inline mail delivery is disabled
      def importing_mode
        disable_inline_mail do
          GitHub.importing do
            GitHub::RateLimitedCreation.disable_content_creation_rate_limits do
              # A lot of the import code writes, and I don't want to track it all down right now.
              ActiveRecord::Base.connected_to(role: :writing) do
                yield
              end
            end
          end
        end
      end

      def disable_inline_mail
        old_delivery_method = ActionMailer::Base.delivery_method
        ActionMailer::Base.delivery_method = :test
        yield
      ensure
        ActionMailer::Base.delivery_method = old_delivery_method
      end

      # Internal: Read the serialized models for model_type from the extracted
      # archive, yielding the block with the parsed contents of each file.
      #
      # model_type - String singular name of model.
      def get_serialized_models_from_archive(model_type)
        begin
          pattern = "#{model_type.pluralize}_*.json"
          read_from_archive(pattern) do |file|
            serialized_models = GitHub::JSON.parse(file.read)
            yield(serialized_models) unless serialized_models.empty?
          end
        rescue Errno::ENOENT
          # noop
        end
      end

      # Internal: Find migratable resources in a batch query by source_url and
      # return them in a hash accessible by their source_url.
      #
      # serialized_models - Array of hashes with url attribute.
      #
      # Returns a Hash.
      def migratable_resources_for_serialized_models_by_url(serialized_models)
        urls = serialized_models.map { |serialized_model| serialized_model["url"] }
        migratable_resources = current_migration.where(source_url: urls)

        migratable_resources.each_with_object(CaseInsensitiveHash.new).each do |mr, hash|
          hash[mr.source_url] = mr
        end
      end

      # Internal: Find models for migratable resources and return them in a hash
      # accessible by their id.
      #
      # migratable_resources - Array of MigratableResource objects.
      #
      # Returns a Hash.
      def models_for_migratable_resources_by_id(migratable_resources, scope: nil, joins: [], skip_joins: false)
        if scope.nil?
          model_types = migratable_resources.map(&:model_type).uniq
          raise "migratable resources must have same model_type" if model_types.size > 1
          scope = model_types.first.camelize.constantize
        end

        scope = scope.includes(joins) unless skip_joins
        models = scope.find(migratable_resources.map(&:model_id).compact)
        models.each_with_object({}) { |model, hash| hash[model.id] = model }
      end

      # Internal: Throttler used for throttling records processed per second.
      #
      # Returns a GitHub::Throttler::PerSecond.
      def per_second_throttler
        @per_second_throttler ||= GitHub::Throttler::PerSecond.new(per_second: per_second)
      end

      def schema_version
        @schema_version ||= SchemaVersion.new
      end

      # Internal: Extract the schema version from the archive.
      def archive_schema_version
        if @archive_schema_version.nil?
          read_from_archive("schema.json") do |file|
            data = GitHub::JSON.parse(file.read)
            @archive_schema_version = data["version"]
          end
          @archive_schema_version ||= false
        end

        @archive_schema_version || nil
      end

      # Internal: Build instance of UrlTranslator with correct from template.
      def url_translator
        @url_translator ||= begin
          templates = archive_url_templates
          if templates
            UrlTranslator.new(from: templates)
          else
            UrlTranslator.new
          end
        end
      end

      def source_url_templates
        url_translator.from
      end

      # Internal: Fetch url template based on migratable resource model type
      def model_url_template(model_type, attributes)
        # Certain models have mulitple templates based on if they are tied to an issue or pull request
        # Extracted the nested template based on the existance of a parent issue or pull_request key in attributes
        if %w(issue_comment issue_event).include?(model_type)
          issue_or_pull_request_key = (attributes.keys & %w(issue pull_request)).first
          source_url_templates[model_type][issue_or_pull_request_key]
        else
          source_url_templates[model_type]
        end
      end

      # Internal: Extract urls.json from archive or default to DefaultUrlTemplates.
      #
      # Returns a Hash.
      def archive_url_templates
        @archive_url_templates ||= begin
          templates = DefaultUrlTemplates

          read_from_archive("urls.json") do |file|
            templates = GitHub::JSON.parse(file.read)
          end

          templates.tap do |t|
            key = "migrationUrlTemplates-#{guid}"

            ActiveRecord::Base.connected_to(role: :writing) do
              GitHub::Migrator::KV.store.set(key, t.to_json)
            end
          end
        end
      end

      def migration_source_from_url_templates(url_templates)
        case url_templates
        when GitHub::Migrator::GitLabUrlTemplates then "GitLab"
        when GitHub::Migrator::BitBucketServerUrlTemplates, GitHub::Migrator::BitBucketServerUrlTemplatesReleasesNotEncoded  then "BitBucket"
        when GitHub::Migrator::DefaultUrlTemplates then "GitHub"
        else
          "Unknown"
        end
      end

      # Internal: Does this schema support translating urls?
      # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
      def translate_urls?
        @translate_urls ||= schema_version.can_translate_urls?(archive_schema_version)
      end
      # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

      # Internal: Content rewriter class used in post processors.
      #
      # Returns a UserContentRewriter.
      def user_content_rewriter
        @user_content_rewriter ||= UserContentRewriter.new(
          current_migration: current_migration,
        )
      end
    end
  end
end
