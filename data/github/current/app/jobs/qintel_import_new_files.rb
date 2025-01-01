# typed: true
# frozen_string_literal: true

class QintelImportNewFiles < ApplicationJob
  queue_as :qintel_import_new_files
  # This job is stateless and should be retried if a worker is killed.
  retry_on_dirty_exit

  schedule interval: 1.minute, condition: -> { !GitHub.enterprise? }

  locked_by timeout: 10.minutes, key: ->(_job) {
    "qintel_import_file"
  }

  # Occasionally the qintel API will timeout attempting to get the list
  # of files. When this happens we can attempt to retry the job. We'll
  # retry 5 times, waiting 3 seconds between attempts before ultimately
  # logging the error to failbot. Retrying isn't urgent since we schedule
  # the job to run often. However its nice to reduce the noise unless
  # there is a real issue (which there likely is if the retried jobs
  # continue to timeout)
  retry_on GitHub::Qintel::TimeoutError

  # We've seen a few cases where things like DNS lookups will briefly fail
  # for one run throwing a request failed error. We can simply retry on this
  # error as well
  retry_on GitHub::Qintel::RequestFailed

  MAX_PARALLEL_IMPORTS = 1

  def queue_length
    QintelImportFile.queue_depth
  end

  def perform
    clean_local_files
    report_stats

    return if queue_length >= MAX_PARALLEL_IMPORTS
    return if file_uuids_to_process.empty?

    file_uuids_to_process.each do |uuid|
      # No more parallel imports permitted
      return if queue_length >= MAX_PARALLEL_IMPORTS

      QintelImportFile.perform_later(uuid: uuid)
    end
  end

  def clean_local_files
    uuids_to_clean = file_uuids_imported_after(DateTime.now - 30.days)
    uuids_to_clean.each do |uuid|
      local_file_path = GitHub::Qintel::CredentialFile.get_local_file_path(uuid)
      if File.exist? local_file_path
        begin
          File.delete local_file_path
        rescue Errno::ENOENT
        end
      end
    end
  end

  def report_stats
    unfinished = semi_imported_files

    report_semi_imported_file_durations unfinished
    GitHub.dogstats.gauge("qintel.files.new", new_file_uuids.count)
    GitHub.dogstats.gauge("qintel.files.semi_imported", unfinished.count)
    GitHub.dogstats.gauge("qintel.files.unimported", file_uuids_to_process.count)
  end

  def report_semi_imported_file_durations(unfinished)
    unfinished.each do |file|
      elapsed = GitHub::Dogstats.duration(file.created_at, Time.now.utc)
      GitHub.dogstats.distribution("qintel.files.semi_imported.duration", elapsed)
    end
  end

  def file_uuids_to_process
    @file_uuids_to_process ||= new_file_uuids + semi_imported_file_uuids
  end

  def new_file_uuids
    @new_file_uuids ||= begin
      in_feed_raw = available_files.map(&:raw)
      in_feed_uuids = in_feed_raw.map do |file|
        file[:fileuuid]
      end

      # filter all the uuids we know about
      new_uuids = T.let([], T::Array[String])
      existing_uuids = in_feed_uuids.each_slice(1000) do |uuid_slice|
        existing = CompromisedPasswordDatasource.where(
          name: "qintel",
        ).where(version: in_feed_uuids).pluck(:version)
        new_uuids += uuid_slice - existing
      end
      new_uuids
    end
  end

  def available_files
    @available_files ||= GitHub::Qintel::Catalog.fetch.credential_files.sort_by do |file|
      file.crack_count
    end
  end

  def semi_imported_file_uuids
    @semi_imported_file_uuids ||= semi_imported_files.map(&:version)
  end

  def semi_imported_files
    CompromisedPasswordDatasource.where(
      name: "qintel",
      import_finished_at: nil,
    ).to_a
  end

  def file_uuids_imported_after(date)
    CompromisedPasswordDatasource.where(
      name: "qintel",
    ).where("import_finished_at > ?", date).pluck(:version)
  end
end
