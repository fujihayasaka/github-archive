# typed: true
# frozen_string_literal: true

module GitHub::Storage
  class RebuildHostCommand < Command
    def initialize(host: nil, dir: nil, log_io: nil, dry_run: false)
      @host = host || GitHub.local_storage_host_name
      @dir = dir || GitHub.storage_data_path
      super(log_io: log_io, dry_run: dry_run)
    end

    def perform
      if @host.blank? || @dir.blank? || fileserver.nil?
        log("No Storage::FileServer for #{@host.inspect}")
        return
      end

      log("rebuilding #{@host.inspect} from objects in #{@dir.inspect}#{" (dry run)" if dry_run?}")

      oids = []
      Dir.glob("#{@dir}/**/*") do |path|
        next unless File.file?(path)
        if dry_run?
          log("rebuild: %s", path)
          next
        end

        oid = File.basename(path)
        size = File.size(path)
        GitHub::Storage::Creator.create_blob(oid: oid, size: size)
        oids << oid
      end

      oids.each_slice(100) do |batch|
        blobs = ::Storage::Blob.where(oid: batch).all
        GitHub::Storage::Creator.create_replicas_from_repair(@host, blobs.map(&:id))

        blobs_by_oid = blobs.index_by(&:oid)
        batch.each do |oid|
          log("rebuild: %s", oid)
        end
      end
    end

    private

    def fileserver
      @fileserver ||= ::Storage::FileServer.where(host: @host).first
    end
  end
end
