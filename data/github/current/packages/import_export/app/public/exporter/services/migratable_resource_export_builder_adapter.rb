# typed: strict
# frozen_string_literal: true

module Exporter::Services
  # Adapts the MigratableResourceExportBuilder interface to use BatchBuilder
  # This class bridges the old MigratableResource creation logic with the new
  # BatchBuilder architecture, maintaining the same interface while leveraging
  # improved batching and observability
  class MigratableResourceExportBuilderAdapter
    BATCH_SIZE = 1000
    MAX_RETRIES = 5
    DEFAULT_PROGRESS = T.let(lambda { |_type, _value| }, T.proc.params(type: Symbol, count: Integer).void)

    sig do
      params(
        guid: String,
        model_url_service: GitHub::Migrator::ModelUrlService,
        progress: T.proc.params(type: Symbol, count: Integer).void,
        exclude_git_data: T::Boolean,
        org_metadata_only: T::Boolean,
        batch_size: Integer
      ).void
    end
    def initialize(guid:, model_url_service:, progress: DEFAULT_PROGRESS, exclude_git_data: false, org_metadata_only: false, batch_size: BATCH_SIZE)
      @guid              = guid
      @model_url_service = model_url_service
      @progress          = progress
      @exclude_git_data  = exclude_git_data
      @org_metadata_only = org_metadata_only
      @batch_size        = batch_size
      @migration         = T.let(nil, T.nilable(Migration))
      @user_ids          = T.let(Set.new, T::Set[Integer])
      @batch_builder     = T.let(nil, T.nilable(Exporter::BatchBuilder))
    end

    sig { returns(String) }
    attr_reader :guid

    sig { returns(GitHub::Migrator::ModelUrlService) }
    attr_reader :model_url_service

    sig { returns(T.proc.params(type: Symbol, count: Integer).void) }
    attr_reader :progress

    sig { params(model: T.nilable(T.any(ApplicationRecord::Base, T::Hash[Symbol, Integer]))).void }
    def add(model)
      case model
      when Hash
        user_id = model.fetch(:user_id)
        user_ids.add(user_id)
      when nil
        nil  # skip adding unreferenceable models
      else
        batch_builder.add_model(model)
      end
    end

    sig { void }
    def complete
      # Queue any batches accumulated so far
      batch_builder.queue_batches

      # Process users with error handling
      process_user_batches

      # Queue all remaining batches after user processing
      batch_builder.queue_batches
    end

    sig { params(model: T.nilable(T.any(ApplicationRecord::Base, T::Hash[Symbol, Integer]))).void }
    def add_now(model)
      add(model)

      # Flush batches for the specific model type
      case model
      when Hash
        # For hashes (user references), flush User batches
        batch_builder.flush_batches_for("user")
      when nil
        # No-op for nil models
        nil
      else
        # For regular models, flush batches for their type
        model_type = model.class.model_name.to_s.underscore
        batch_builder.flush_batches_for(model_type)
      end
    end

    private

    sig { void }
    def process_user_batches
      # Process accumulated user_ids
      user_ids.each_slice(BATCH_SIZE) do |ids|
        begin
          # Wrap user processing in ConnectionRetry for database errors
          Exporter::ConnectionRetry.with_retry(
            migration: T.must(migration),
            query_name: :process_user_batch,
            max_retries: MAX_RETRIES
          ) do
            User.throttle_with_retry(max_retry_count: MAX_RETRIES) do
              User.where(id: ids).each do |user|
                # Skip users that don't have a valid URL (e.g., deleted users)
                next if url_for_model(user).nil?

                batch_builder.add_model(user)
              end
            end
          end
        rescue StandardError => e
          GitHub.logger.error(
            "Error processing user batch",
            migration_guid: @guid,
            batch_size: ids.size,
            error: e.message
          )
        end
      end
    end

    delegate :url_for_model, to: :@model_url_service

    sig { returns(T.nilable(Migration)) }
    def migration
      @migration ||= Migration.find_by(guid: @guid)
    end

    sig { returns(T::Set[Integer]) }
    def user_ids
      @user_ids
    end

    sig { returns(Exporter::BatchBuilder) }
    def batch_builder
      @batch_builder ||= T.let(
        Exporter::BatchBuilder.new(
          migration: T.must(migration),
          options: Exporter::ExportOptions.new(
            exclude_git_data: @exclude_git_data,
            org_metadata_only: @org_metadata_only
          ),
          progress: @progress,
          batch_size: @batch_size
        ),
        T.nilable(Exporter::BatchBuilder)
      )
      @batch_builder
    end
  end
end
