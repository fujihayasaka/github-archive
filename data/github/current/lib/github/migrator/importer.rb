# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class Importer
      UPLOAD_RETRIES = 3

      RETRYABLE_ERRORS = [
        Net::ReadTimeout,
        Errno::ECONNRESET,
        Errno::EPIPE,
        Errno::ETIMEDOUT,
        Faraday::ConnectionFailed,
        Faraday::TimeoutError,
        ::Storage::Policy::HttpError
      ].freeze

      def initialize(options = nil)
        @importer_options = options || {}
        @current_migration = @importer_options[:current_migration]
        @migration_path = @importer_options[:migration_path]
        @archive_import_path = @importer_options[:archive_import_path]
        @actor = @importer_options[:actor]
        @model_url_service = @importer_options[:model_url_service]
        @cache = @importer_options[:cache] || Cache.null
        @migration_guid = @current_migration&.guid
      end

      def inspect
        if current_migration
          "#<#{self.class.name} guid: \"#{current_migration.guid}\">"
        else
          "#<#{self.class.name} ...>"
        end
      end

      def import(attributes, options = {})
        # noop
      end

      def merge(attributes, model)
        # noop
      end

      def self.warnings_for(attributes, options = {})
        []
      end

      protected

      def import_allowed?
        return true if GitHub.enterprise?
        return true unless Rails.env.production?
        @actor && @actor.feature_flag_enabled?(:gh_migrator_import_to_dotcom, default: false)
      end

      private

      attr_reader :current_migration, :migration_path, :archive_import_path,
        :importer_options, :cache, :migration_guid

      # Public: Actor used when creating objects that need an org admin.
      #
      # Returns a user.
      attr_reader :actor

      def model_from_source_url(source_url)
        return unless source_url
        return unless current_migration

        cache.getset("model:by_source_url:#{source_url}") do
          current_migration.by_source_url(source_url).model
        end
      end

      def user_or_fallback(source_url)
        model_from_source_url(source_url) || User.ghost
      end

      def model_from_source_url!(source_url)
        return unless source_url

        model_from_source_url(source_url).tap do |model|
          if model.blank?
            message  = "Unable to find model for #{source_url}"
            raise AssociationFailed.new(message)
          end
        end
      end

      def last_part_of_url(url)
        return unless url

        url.split("/").last
      end

      # Internal: Takes validation error message and turns it into a snakecased
      # error code for easier log filtering.
      #
      # error - String validation error.
      #
      # Returns a String or NilClass.
      def error_code(error)
        case error
        when "has already been taken"        then "already_exists"
        when "is invalid"                    then "invalid"
        when "can't be blank"                then "missing_field"
        when "must be a branch"              then "must_be_a_branch"
        when "must be a collaborator"        then "not_a_collaborator"
        when /does not have push access/     then "push_access_required"
        when /No commits between/            then "no_commits_between"
        when /A pull request already exists/ then "pull_request_already_exists"
        end
      end

      # Internal: Import model using direct insert approach. Logs validation
      # errors and continues operation without halting the import.
      #
      # model - GitHub model to import.
      #
      # Returns an instance of an ActiveRecord model.
      def import_model(model)
        # Kick off before and after validation callbacks.
        begin
          model.valid?
        rescue => error # rubocop:todo Lint/RescueException
          GitHub.logger.error({
            :exception => error,
            "code.function" => "import_model",
            "code.namespace" => self.class.name
            }
          )
        end

        validation_error_messages = model.errors.messages

        # Set updated_at and created_at if not already set
        model.updated_at ||= Time.now if model.respond_to?(:updated_at=)
        model.created_at ||= Time.now if model.respond_to?(:created_at=)

        attributes = database_attributes_for(model)

        # Set raw_data field if the model has one.
        #
        # Making an assumption here that the serialized_attribtues field is
        # called "data" because I can't figure out how to get it programatically
        # and it looks like we use "data" everywhere according to
        # `git grep serialized_attributes`.
        if model.respond_to?(:raw_data)
          attributes = attributes.except(*model.raw_data.to_h.keys)
          coder = Coders::Handler.new(model.raw_data.class, compressor: compressor(model))
          attributes["raw_data"] = coder.dump(model.raw_data)
        end

        # build the sql
        insert_manager = Arel::InsertManager.new
        table = Arel::Table.new(model.class.table_name)
        values = []
        attributes.each do |key, value|
          values.push([table[key], value])
        end
        insert_manager.insert(values)
        sql = insert_manager.to_sql

        # insert the record and return the id
        id = model.class.connection.insert(sql) # domain-isolation-query-violation:ignore:packages/issues (INSERT)

        # find the model instance by id
        found_model = model.class.find(id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        # log validation errors to migration log
        validation_error_messages.each_key do |key|
          validation_error_messages[key].each do |validation_error_message|
            log_hash = {
              "code.namespace" => self.class.name,
              "code.function" => "import_model",
              "gh.migration_tools.migration.type" => "repo",
              "gh.migration_tools.migration.model.name" => found_model.class.name.underscore,
              "gh.migration_tools.migration.model.id" => found_model.id,
              "gh.migration_tools.migration.field" => key.to_s
            }
            if code = error_code(validation_error_message)
              log_hash[:code] = code
            end
            log_hash[:validation_error] = validation_error_message
            GitHub.logger.info(log_hash)
          end
        end

        found_model
      end

      # Internal: Returns model attributes in a format that can be persisted to
      # the database. This is necessary because of a change to AR::Enum in
      # Rails. In 4.2, enum columns return their integer values. In future
      # versions, enum columns return their string values. We need the integer
      # values.
      def database_attributes_for(model)
        attributes = model.instance_variable_get(:@attributes).map(&:value_for_database).send(:attributes)
        # Filter out values for virtual columns
        attributes.reject { |key, _value| model.class.columns_hash[key].virtual? }
      end

      # Internal: Import an asset with #import_model.
      def import_asset(asset, file)
        if GitHub.storage_cluster_enabled?
          import_asset_to_cluster(asset, file)
        else
          import_asset_locally(asset, file)
        end
      end

      def import_asset_to_cluster(uploadable, file)
        creator_params = {
          oid: Digest::SHA256.file(file.tempfile).hexdigest,
          size: file.tempfile.size,
          host_urls: GitHub::Storage::Allocator.least_loaded_fileservers,
        }

        uploader_params = creator_params.slice(:oid).merge(file: file.tempfile)
        uploader_params[:fileservers] = creator_params[:host_urls]
        GitHub::Storage::Uploader.perform(uploader_params)

        result = GitHub::Storage::Creator.perform(**creator_params) do |blob|
          uploadable.storage_blob = blob
          uploadable.name = file.original_filename
          uploadable.content_type = file.content_type
          uploadable.state = :uploaded
          import_model(uploadable)
        end
        result
      end

      # "locally" is a misnomer, because it will save the file to disk on GitHub
      # Enterprise, but will upload to S3 on GitHub.com, according to the
      # Storage Policy determined by UserAsset
      def import_asset_locally(asset, file)
        # Update attributes and write the DB record.
        asset.name ||= file.original_filename
        asset.size = file.size
        asset.content_type = file.content_type
        ensure_asset_uploader!(asset)
        asset.save!

        attempt = 1

        begin
          asset.storage_policy(actor: asset.uploader).upload_contents!(file)
        rescue *RETRYABLE_ERRORS => exception
          raise exception if attempt > UPLOAD_RETRIES
          attempt += 1

          retry
        end

        asset.track_uploaded || asset.save!
        asset
      end

      # Internal: ModelUrlService handles url_for_model and model_for_url lookups.
      # It caches lookups to speed up migrations.
      #
      # Returns a ModelUrlService.
      def model_url_service
        @model_url_service ||= ModelUrlService.new
      end
      delegate :url_for_model, :model_for_url, to: :model_url_service

      def ensure_asset_uploader!(asset)
        return if asset.valid?(:create)
        if !asset.uploader || asset.errors[:uploader_id].any? { |msg| msg =~ /does not have push access/ }
          asset.uploader = @actor
        end
      end

      # Determine which compressor to use when encoding/decoding raw_data
      def compressor(model)
        case model
        when IssueEvent then GitHub::ZPack
        else GitHub::ZSON
        end
      end

      def log_and_create_importer_result(attributes, error, warning, model_type, resolution)
        GitHub.logger.error(warning, {
          :exception => error,
          "code.function" => "import",
          "code.namespace" => self.class.to_s,
          "gh.migration_tools.migration.type" => "repo",
          "gh.migration_tools.migration.model.name" => model_type,
          "gh.migration_tools.migration.model.source_url" => attributes["url"],
          "gh.migration_tools.migration.model.resolution" => resolution,
          "gh.migration_tools.migration.guid" => migration_guid
          }
        )

        ImporterResult.new(nil, warning: warning)
      end
    end
  end
end
