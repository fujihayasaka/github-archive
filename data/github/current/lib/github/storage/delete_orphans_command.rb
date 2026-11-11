# typed: true
# frozen_string_literal: true

module GitHub::Storage
  class DeleteOrphansCommand < Command
    def initialize(log_io: nil, dry_run: false)
      super(log_io: log_io, dry_run: dry_run)
    end

    def perform
      log("gathering and deleting orphaned objects#{' (dry run)' if dry_run?}...")

      blobs = GitHub::Storage::Replica.get_orphaned_oids

      if blobs.size == 0
        log("no orphaned objects found")
        return
      end

      if dry_run?
        log("would delete #{blobs.size} orphaned objects")
      end

      blobs.each_slice(100) do |batch|
        unless dry_run?
          batch_ids = batch.map { |results| results[0] }
          GitHub::Storage::Destroyer.finalize_purge_for(batch_ids)
        end


        batch.each do |result|
          log("#{dry_run? ? 'would delete' : 'deleted'} orphan: %s", result[1])
        end
      end
    end
  end
end
