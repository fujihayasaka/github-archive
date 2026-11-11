# typed: strict
# frozen_string_literal: true

require "json"
require "time"

module RetroactiveImmutability
  class MigrationState
    Status = T.type_alias { T::Hash[Symbol, T.untyped] }
    Progress = T.type_alias { T::Hash[Symbol, T.untyped] }
    FailedRow = T.type_alias { T::Hash[Symbol, T.untyped] }

    TTL = T.let(5.minutes, ActiveSupport::Duration)

    sig { params(repo: ::Repository).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def self.read(repo)
      status = read_status(repo)
      return nil unless status

      status.merge(read_progress(repo) || default_progress)
    end

    sig { params(repo: ::Repository, state: T::Hash[T.any(String, Symbol), T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def self.write(repo, state)
      normalized_state = normalize_state(state)

      status = write_status(
        repo,
        status: normalized_state.fetch(:status),
        run_number: normalized_state.fetch(:run_number),
        started_at: T.cast(normalized_state[:started_at], T.nilable(Time)),
        updated_at: T.cast(normalized_state[:updated_at], T.nilable(Time)),
      )

      progress = write_progress(
        repo,
        migrated: normalized_state.fetch(:migrated),
        failed: normalized_state.fetch(:failed),
        cursor: T.cast(normalized_state[:cursor], T.nilable(Integer)),
        failed_rows: T.cast(normalized_state[:failed_rows], T::Array[FailedRow]),
      )

      status.merge(progress)
    end

    sig { params(repo: ::Repository).returns(T.nilable(Status)) }
    private_class_method def self.read_status(repo)
      raw_value = store.get(status_key(repo)).value { nil }
      return nil if raw_value.nil?

      payload = symbolize_keys(JSON.parse(raw_value))
      payload[:run_number] = payload[:run_number].to_i if payload.key?(:run_number)
      payload[:started_at] = normalize_time(payload[:started_at]) if payload[:started_at]
      payload[:updated_at] = normalize_time(payload[:updated_at]) if payload[:updated_at]
      payload
    end

    sig do
      params(
        repo: ::Repository,
        status: T.any(String, Symbol),
        run_number: Integer,
        started_at: T.nilable(Time),
        updated_at: T.nilable(Time),
      ).returns(Status)
    end
    private_class_method def self.write_status(repo, status:, run_number:, started_at: nil, updated_at: nil)
      payload = T.let({
        status: status.to_s,
        run_number: run_number.to_i,
      }, Status)
      payload[:started_at] = started_at.utc if started_at
      payload[:updated_at] = T.must(updated_at || started_at).utc if updated_at || started_at

      store.set(status_key(repo), encode(payload), expires: TTL.from_now)
      payload
    end

    sig { params(repo: ::Repository).returns(T.nilable(Progress)) }
    private_class_method def self.read_progress(repo)
      raw_value = store.get(progress_key(repo)).value { nil }
      return nil if raw_value.nil?

      payload = symbolize_keys(JSON.parse(raw_value))
      payload[:migrated] = payload.fetch(:migrated, 0).to_i
      payload[:failed] = payload.fetch(:failed, 0).to_i
      payload[:cursor] = payload[:cursor].to_i if payload[:cursor]
      payload[:failed_rows] = normalize_failed_rows(payload[:failed_rows])
      payload
    end

    sig do
      params(
        repo: ::Repository,
        migrated: Integer,
        failed: Integer,
        cursor: T.nilable(Integer),
        failed_rows: T::Array[T::Hash[T.any(String, Symbol), T.untyped]],
      ).returns(Progress)
    end
    private_class_method def self.write_progress(repo, migrated: 0, failed: 0, cursor: nil, failed_rows: [])
      deduped_failed_rows = dedupe_failed_rows(failed_rows)

      payload = T.let({
        migrated: migrated.to_i,
        failed: [failed.to_i, deduped_failed_rows.size].max,
        cursor: cursor&.to_i,
        failed_rows: deduped_failed_rows,
      }, Progress)

      store.set(progress_key(repo), encode(payload), expires: TTL.from_now)
      payload
    end

    sig { params(repo: ::Repository, amount: Integer).returns(Integer) }
    def self.increment_migrated(repo, amount: 1)
      progress = read_progress(repo) || default_progress
      updated_progress = write_progress(
        repo,
        migrated: progress.fetch(:migrated) + amount.to_i,
        failed: progress.fetch(:failed),
        cursor: T.cast(progress[:cursor], T.nilable(Integer)),
        failed_rows: T.cast(progress[:failed_rows], T::Array[FailedRow]),
      )

      updated_progress.fetch(:migrated)
    end

    sig do
      params(
        repo: ::Repository,
        release_id: Integer,
        tag_name: T.nilable(String),
        reason: String,
        message: String,
      ).returns(T::Array[FailedRow])
    end
    def self.append_failed_row(repo, release_id:, tag_name:, reason:, message:)
      progress = read_progress(repo) || default_progress
      failed_rows = T.cast(progress[:failed_rows], T::Array[FailedRow]).dup
      failed_rows << normalize_failed_row(
        release_id:,
        tag_name:,
        reason:,
        message:,
      )

      updated_progress = write_progress(
        repo,
        migrated: progress.fetch(:migrated),
        failed: progress.fetch(:failed),
        cursor: T.cast(progress[:cursor], T.nilable(Integer)),
        failed_rows:,
      )

      T.cast(updated_progress[:failed_rows], T::Array[FailedRow])
    end

    sig { params(repo: ::Repository).returns(NilClass) }
    def self.clear(repo)
      store.mdel([status_key(repo), progress_key(repo)])
      nil
    end

    # Atomically claim the per-repo migration lock by creating the status
    # record. Returns true if acquired, false if a live run already holds it.
    # The record carries a TTL, so a crashed holder is reclaimed automatically
    # once it lapses (setnx prunes the expired row before re-inserting).
    sig { params(repo: ::Repository, started_at: Time).returns(T::Boolean) }
    def self.claim(repo, started_at: Time.now.utc)
      payload = T.let({ status: "running", started_at: started_at.utc }, Status)
      !!store.setnx(status_key(repo), encode(payload), expires: TTL.from_now)
    end

    # Release a lock previously claimed with started_at, but only if we still
    # own it. Comparing started_at avoids deleting a record that a newer run
    # took over after our record's TTL lapsed.
    sig { params(repo: ::Repository, started_at: Time).returns(NilClass) }
    def self.release(repo, started_at:)
      current = read_status(repo)
      clear(repo) if current && same_run?(T.cast(current[:started_at], T.nilable(Time)), started_at)
      nil
    end

    sig { params(repo: ::Repository).returns(Integer) }
    def self.next_run_number(repo)
      store.increment(run_number_key(repo))
    end

    sig { params(repo: ::Repository).returns(String) }
    private_class_method def self.status_key(repo)
      "immutable_release_migration:status:repo:#{repo.id}"
    end

    sig { params(repo: ::Repository).returns(String) }
    private_class_method def self.progress_key(repo)
      "immutable_release_migration:progress:repo:#{repo.id}"
    end

    sig { params(repo: ::Repository).returns(String) }
    private_class_method def self.run_number_key(repo)
      "immutable_release_migration:run_number:repo:#{repo.id}"
    end

    sig { returns(GitHub::KV) }
    private_class_method def self.store
      Kv.store
    end

    sig { returns(Progress) }
    private_class_method def self.default_progress
      {
        migrated: 0,
        failed: 0,
        cursor: nil,
        failed_rows: [],
      }
    end

    sig { params(stored: T.nilable(Time), expected: Time).returns(T::Boolean) }
    private_class_method def self.same_run?(stored, expected)
      return false unless stored

      stored.utc.iso8601(6) == expected.utc.iso8601(6)
    end

    sig { params(state: T::Hash[T.any(String, Symbol), T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    private_class_method def self.normalize_state(state)
      normalized_state = symbolize_keys(state)
      normalized_state[:status] = normalized_state.fetch(:status, normalized_state[:state]).to_s
      normalized_state[:run_number] = normalized_state.fetch(:run_number).to_i
      normalized_state[:started_at] = normalize_time(normalized_state[:started_at]) if normalized_state[:started_at]
      normalized_state[:updated_at] = normalize_time(normalized_state[:updated_at]) if normalized_state[:updated_at]
      normalized_state[:migrated] = normalized_state.fetch(:migrated, normalized_state[:succeeded]).to_i
      normalized_state[:failed] = normalized_state.fetch(:failed, 0).to_i
      normalized_state[:cursor] = normalized_state[:cursor].to_i if normalized_state[:cursor]
      normalized_state[:failed_rows] = normalize_failed_rows(normalized_state[:failed_rows])
      normalized_state
    end

    sig { params(rows: T.untyped).returns(T::Array[FailedRow]) }
    private_class_method def self.normalize_failed_rows(rows)
      return [] unless rows.is_a?(Array)

      dedupe_failed_rows(rows)
    end

    sig { params(rows: T::Array[T::Hash[T.any(String, Symbol), T.untyped]]).returns(T::Array[FailedRow]) }
    private_class_method def self.dedupe_failed_rows(rows)
      seen_release_ids = T.let({}, T::Hash[Integer, T::Boolean])

      rows.each_with_object([]) do |row, deduped_rows|
        symbolized_row = symbolize_keys(row)
        normalized_row = normalize_failed_row(
          release_id: symbolized_row.fetch(:release_id).to_i,
          tag_name: symbolized_row[:tag_name]&.to_s,
          reason: symbolized_row.fetch(:reason).to_s,
          message: symbolized_row.fetch(:message).to_s,
        )
        next if seen_release_ids[normalized_row.fetch(:release_id)]

        seen_release_ids[normalized_row.fetch(:release_id)] = true
        deduped_rows << normalized_row
      end
    end

    sig do
      params(
        release_id: Integer,
        tag_name: T.nilable(String),
        reason: String,
        message: String,
      ).returns(FailedRow)
    end
    private_class_method def self.normalize_failed_row(release_id:, tag_name:, reason:, message:)
      {
        release_id: release_id.to_i,
        tag_name: tag_name,
        reason: reason.to_s,
        message: message.to_s,
      }
    end

    sig { params(value: T.untyped).returns(Time) }
    private_class_method def self.normalize_time(value)
      return value.utc if value.respond_to?(:utc)

      Time.iso8601(value.to_s).utc
    end

    sig { params(hash: T::Hash[T.any(String, Symbol), T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    private_class_method def self.symbolize_keys(hash)
      hash.each_with_object({}) do |(key, value), memo|
        memo[key.to_sym] = value
      end
    end

    sig { params(value: T.untyped).returns(T.untyped) }
    private_class_method def self.encode_value(value)
      case value
      when Time
        value.iso8601(6)
      when Array
        value.map { encode_value(_1) }
      when Hash
        value.each_with_object({}) { |(key, nested_value), memo| memo[key.to_s] = encode_value(nested_value) }
      else
        value
      end
    end

    sig { params(value: T.untyped).returns(String) }
    private_class_method def self.encode(value)
      JSON.generate(encode_value(value))
    end
  end
end
