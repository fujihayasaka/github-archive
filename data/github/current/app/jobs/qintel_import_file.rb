# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class QintelImportFile < ApplicationJob
  LOCK_TIMEOUT = 1.hour
  TIME_LIMIT = 45.minutes

  queue_as :qintel_import_file

  # This job is stateless and should be retried if a worker is killed.
  retry_on_dirty_exit

  locked_by timeout: LOCK_TIMEOUT, key: ->(job) {
    args = job.arguments.first
    "#{args[:uuid]}:#{args[:start].to_i}"
  }

  MAX_JOB_ATTEMPTS = 5
  MAX_CONCURRENT_JOBS = 40

  # This just needs to be sufficiently long to complete a batch of creds
  # from the file and is used to ensure we don't orphan the key in KV
  JOB_KEY_TTL = 2.weeks

  # Rarely occurs when 2 jobs are importing extremely similar files
  # we try to handle this in the job its self but sometimes
  # we can't and the best way to solve this issue is to wait
  # wait until those rows are unlocked
  retry_on(ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: MAX_JOB_ATTEMPTS) do |_job, error|
    Failbot.report!(error)
  end

  retry_on(GitHub::Restraint::UnableToLock, wait: 5.minutes, attempts: MAX_JOB_ATTEMPTS) do |_job, error|
    Failbot.report!(error)
  end

  # We can process approximately 100k records in less than 5 minutes
  BATCH_SIZE = 5_000

  def perform(uuid:, start: nil)
    return if GitHub.flipper[:disable_qintel_imports].enabled?
    return if uuid.empty?

    # The key used to store values in KV
    job_key = "qintel:#{uuid}"

    # We don't want to rely on KV to be able to process
    # the job but if no start value was provided we can
    # attempt to resume the job based on the last save
    # point. If there is no savepoint resort to 0
    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:qintel_import_file"])
    start ||= GitHub::Authentication::KV.store.get(job_key).value { 0 }.to_i

    lock_key = restraint_key(uuid)
    log(
      "attempting to acquire lock",
      "gh.import_file_job.uuid" => uuid,
      "gh.import_file_job.lock_key" => lock_key,
      "gh.import_file_job.initial_position" => start,
    )

    GitHub::SafeTimer.timeout(TIME_LIMIT) do |timer|
      GitHub::Restraint.new.lock!(lock_key, 1, TIME_LIMIT) do
        return if already_imported?(uuid)

        file = GitHub::Qintel::CredentialFile.new(hash: {
          fileuuid: uuid,
        })

        time_expired = T.let(false, T::Boolean)
        file.fetch do |parser|
          # While we have the file open,
          # Let's try and process as many batches as we can
          while (parsed_credentials = parser.parse_credentials_from_file(start: start, amount: BATCH_SIZE)).any?
            save_start_position(job_key, start)
            break if GitHub.flipper[:disable_qintel_imports].enabled?

            log(
              "starting batch",
              "gh.import_file_job.uuid" => uuid,
              "gh.import_file_job.lock_key" => lock_key,
              "gh.import_file_job.position" => start,
              "gh.import_file_job.batch_size" => parsed_credentials.length,
            )

            if timer.expired?
              GitHub.dogstats.increment("qintel_import_file.time_limit_exceeded")
              time_expired = true
              break
            end

            ActiveRecord::Base.connected_to(role: :writing) do
              CompromisedPasswordDatasource.store_passwords(
                name: "qintel",
                version: parser.uuid,
                sha1_passwords: each_password_digest(parsed_credentials)
              )

              CompromisedPasswordDatasource.check_for_compromise(
                compromised_records: parsed_credentials,
                name: "qintel",
                version: parser.uuid,
              )
            end

            start += parsed_credentials.length
          end
        end
        break if GitHub.flipper[:disable_qintel_imports].enabled?


        if !time_expired
          log(
            "import completed",
            "gh.import_file_job.uuid" => uuid,
            "gh.import_file_job.lock_key" => lock_key,
          )

          ActiveRecord::Base.connected_to(role: :writing) do
            datasource = CompromisedPasswordDatasource.find_by(name: "qintel", version: file.uuid, import_finished_at: nil)
            datasource.mark_import_as_finished! if datasource

            begin
              GitHub.dogstats.increment("authn_kv", tags: ["action:delete", "callsite:qintel_import_file"])
              GitHub::Authentication::KV.store.del(job_key)
            rescue GitHub::KV::UnavailableError
              GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :qintel_import_file, action: :del })
            end
          end

          begin
            File.delete(file.local_file_path) if File.exist?(file.local_file_path)
          rescue Errno::ENOENT
          end
        end
      end
    end
  end

  def already_imported?(uuid)
    already_imported = CompromisedPasswordDatasource.
      where(name: "qintel", version: uuid).
      where.not(import_finished_at: nil)

    if already_imported.exists?
      tags = [
        "datasource:qintel",
        "version:#{uuid}",
      ]
      GitHub.dogstats.increment("qintel.files.already_imported", tags: tags)
      return true
    end

    false
  end

  def save_start_position(job_key, current_index)
    ActiveRecord::Base.connected_to(role: :writing) do
      begin
        GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:qintel_import_file"])
        GitHub::Authentication::KV.store.set(job_key, current_index.to_s, expires: JOB_KEY_TTL.from_now)
      rescue GitHub::KV::UnavailableError
        GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :qintel_queue_next_batch, action: :increment })
      end
    end
  end

  def each_password_digest(parsed_credentials)
    unless block_given?
      return enum_for(:each_password_digest, parsed_credentials)
    end

    parsed_credentials.each do |_username, password|
      next if password.blank?
      yield Digest::SHA1.hexdigest(password) # rubocop:disable GitHub/InsecureHashAlgorithm
    end
  end

  def restraint_key(uuid)
    # sum the character ordinals of the uuid and mod by the max number of concurrent jobs. this should be fairly
    # evenly distributed, but not guaranteed to be so.  Because this "hash" is consistent, we can ensure that the
    # same job cannot be run twice at the same time.
    pool_number = uuid.chars.map { |c| c.ord }.inject(:+) % MAX_CONCURRENT_JOBS
    GitHub.dogstats.increment("qintel_import_file.pool_number", tags: ["pool_number:#{pool_number}"])
    "qintel:#{pool_number}"
  end

  def log(msg, **kwargs)
    GitHub.logger.info(msg, {
      "code.namespace": self.class.name,
    }.merge(kwargs))
  end
end
