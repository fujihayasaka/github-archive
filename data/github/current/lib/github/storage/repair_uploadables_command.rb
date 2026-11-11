# typed: true
# frozen_string_literal: true

require "github/sql/readonly"

module GitHub::Storage
  class RepairUploadablesCommand < Command
    VALID_UPLOADABLES = {
      "Avatar" => Avatar,
      "Marketplace::ListingScreenshot" => Marketplace::ListingScreenshot,
      "Media::Blob" => Media::Blob,
      "MigrationFile" => MigrationFile,
      "OauthApplicationLogo" => OauthApplicationLogo,
      "ReleaseAsset" => ReleaseAsset,
      "RepositoryFile" => RepositoryFile,
      "UploadManifestFile" => UploadManifestFile,
      "UserAsset" => UserAsset,
    }

    def initialize(class_name: nil, ids: nil, log_io: nil, dry_run: false)
      @class_name = class_name
      @ids = Array(ids)
      super(log_io: log_io, dry_run: dry_run)
    end

    def perform
      klass = VALID_UPLOADABLES[@class_name.to_s]
      if !klass
        log("Invalid Uploadable: #{@class_name.inspect}")
        return
      end

      each_record(klass) do |record|
        log("restore reference: #{@class_name}##{record.id}")
        next if dry_run?

        creator_args = {
          oid: record.oid,
          size: record.size,
          host_urls: GitHub::Storage::Allocator.hosts_for_oid(record.oid).
            map { |h| GitHub.storage_replicate_fmt % h },
        }

        GitHub::Storage::Creator.perform(**creator_args) do |blob|
          if record.storage_blob_id != blob.id
            record.update!(storage_blob_id: blob.id)
          end
          record
        end
      end
    end

    private

    def each_record(klass, &block)
      if @ids.present?
        log("repairing #{klass.name}, ids: #{@ids.inspect}#{" (dry run)" if dry_run?}")
        klass.where(id: @ids).all.each do |record|
          block.call(record)
        end
        return
      end

      log("repairing #{klass.name}#{" (dry run)" if dry_run?}")
      iterator = GitHub::QueryBatching::ScopeIterator.new(klass.all, batch_size: 100)
      GitHub::SQL::Readonly.new(iterator.batches, allow_slow_queries: true).each do |records|
        records.each do |record|
          block.call(record)
        end
      end
    end
  end
end
