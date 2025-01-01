# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class SyncAssetUsageParserJob < SyncAssetUsageJob
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  LOCK_WAIT_EXP = read_int_from_env("LOCK_WAIT_EXP", 2)
  LOCK_WAIT_MULT = read_int_from_env("LOCK_WAIT_MULT", 1)
  LOCK_TRIES = read_int_from_env("LOCK_TRIES", 20)

  retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 5)
  retry_on GitHub::Restraint::UnableToLock,
    wait: ->(executions) { executions**LOCK_WAIT_EXP * LOCK_WAIT_MULT.minutes }, attempts: LOCK_TRIES
  retry_on Freno::Throttler::Error, wait: ->(executions) { executions**3 * 30.seconds }, attempts: 8

  GIGABYTE = (1024**3).to_f
  OBJECT_KEY_MATCHER = %r{\A/alambic/media/\d+/}
  MINIMUM_LOG_PARTS = 13

  MAX_JOBS = read_int_from_env("MAX_JOBS", 1)
  TXN_SIZE = read_int_from_env("TXN_SIZE", 20)

  queue_as :sync_asset_usage_parser

  # log_keys - The AWS S3 log file object keys we should download and process.
  def perform(log_keys)
    restraint = GitHub::Restraint.new
    restraint.lock!(T.must(self.class.name), MAX_JOBS, 15.minutes) do
      stat_gauge "passed_logs", log_keys.size

      stat_time("parse") do
        # S3 logs aren't returned in a consistent order and in some cases
        # won't be returned at all.  However, we don't try to look backwards
        # to find straggling logs as we expect them to be relatively few.
        # So we just parse forwards from the marker, ensuring that we always
        # move ahead.
        perform!(log_scanner, log_keys)
      end
    end
  rescue *RETRYABLE_ERRORS => err
    stat_incr "error_retry"
    raise err
  rescue GitHub::Restraint::UnableToLock => err
    stat_incr "lock_error_retry"
    raise err
  end

  def log_scanner
    scanner = super
    # Only tracking Git LFS files right now
    scanner.object_key_matcher = OBJECT_KEY_MATCHER
    scanner.minimum_log_parts = MINIMUM_LOG_PARTS
    scanner
  end

  attr_writer :max_response_time
  def max_response_time
    @max_response_time ||= 0
  end

  def perform!(log_scanner, log_keys)
    logset = Asset::LogScanner::LogSet.new(log_scanner, log_keys)

    net_activities = stat_time("read") do
      parse_s3_logs_by_repository(logset)
    end
    owner_activities = stat_time("aggregate") do
      aggregate_by_owner(net_activities)
    end
    stat_time("save") do
      save_owner_activities(owner_activities)
    end
    stat_time("emit") do
      emit_owner_activities(owner_activities)
    end

    stat_dist "max_logged_response_time", self.max_response_time

    if logset.scan_error?
      # NOTE: Individual log scanning errors are caught in logset.each(),
      #       which adds them to logset.scan_errors, so when they are
      #       present, we re-raise the first one to request job retries up
      #       to the default maximum.  We expect all of these errors to be
      #       subclasses of the Aws::Errors::ServiceError class.
      stat_incr "logset_error"
      raise logset.scan_errors.first
    end
  end

  # Downloads and parses the given log files.
  # Returns multi-dimensional hash to optimize DB insert queries. Each
  # actor+key ID row is kept so we can reject previously seen log files
  # for each owner in #aggregate_by_owner.
  # {
  #   [network_id, repo_id]: {
  #     started_at: {
  #       [actor_id, key_id]: [
  #         {up: 123, down: 123, file: "s3/abc"},
  #         {up: 123, down: 123, file: "s3/abc"},
  #       ]
  #     }
  #   }
  # }
  def parse_s3_logs_by_repository(logset)
    activity = {}
    logset.each do |log, line|
      log_path = "#{log.bucket_name}/#{log.key}"
      aggregate_by_repository(activity, line, log_path)
    end
    activity
  ensure
    stat_gauge "lines", logset.line_count
    stat_gauge "parsed_logs", logset.scan_count
  end

  def aggregate_by_repository(activity, line, log_path)
    return unless item = parse_line(line)

    by_repo = activity[[item[:network_id], item[:repo_id]]] ||= {}
    by_time = by_repo[item[:hour_aligned_time]] ||= {}
    (by_time[[item[:actor_id], item[:key_id]]] ||= []) << {
      up: item[:bandwidth_up].to_f,
      down: item[:bandwidth_down].to_f,
      file: log_path,
    }

    if item[:response_time] > self.max_response_time
      self.max_response_time = item[:response_time]
    end
  end

  # Returns multi-dimensional hash to optimize DB insert queries.
  # {
  #   owner_id: {
  #     customer_id: 456,
  #     repos: {
  #       repo_id: {
  #         started_at: {
  #           [actor_id, key_id]: {up: 123, down: 123, files: []}
  #         }
  #       }
  #     }
  #   }
  # }
  def aggregate_by_owner(activity)
    owners_activity = {}
    activity.keys.in_groups_of(300, false) do |repo_pairs|
      net_ids = repo_pairs.map { |(net_id, _repo_id)| net_id }.compact
      nets = ActiveRecord::Base.connected_to(role: :reading) do
        RepositoryNetwork.
          where(id: net_ids).
          includes(root: :owner).
          all
      end.map { |n| [n.id, n] }.to_h

      repo_pairs.each do |pair|
        net_id, repo_id = *pair
        next unless net = nets[net_id]
        next unless owner = net.network_owner
        organization_id = owner.is_a?(Organization) ? owner.id : nil
        business_id = owner.delegate_billing_to_business? ? owner.business.id : nil
        actor = owner.delegate_billing_to_business? ? owner.business : owner
        customer_id = owner.feature_flag_enabled?(:use_find_or_create_customer, default: true) ? owner.find_or_create_customer.id : (actor.customer&.id || 0)
        by_owner = owners_activity[owner.id] ||= {
          customer_id: customer_id,
          organization_id: organization_id,
          business_id: business_id,
          repos: {}
        }
        by_owner_repo = by_owner[:repos][repo_id] ||= {}

        next unless by_repo = activity[pair]
        by_repo.each do |started_at, actors|
          seen_files = ActiveRecord::Base.connected_to(role: :reading) do
            Asset::Activity.seen_source_files(:lfs, owner.id, repo_id, started_at)
          end
          seen_logs = Set[]
          new_logs = Set[]
          by_time = by_owner_repo[started_at] ||= {}
          actors.each do |actor_id, items|
            by_actor = by_time[actor_id] ||= { up: 0.0, down: 0.0, files: [] }
            items.each do |item|
              if seen_files.include?(item[:file])
                seen_logs << item[:file]
                next
              else
                new_logs << item[:file]
              end

              by_actor[:up] += item[:up]
              by_actor[:down] += item[:down]
              by_actor[:files] << item[:file]
            end
          end
          stat_count "seen_by_repo_hour", seen_logs.size
          stat_count "new_by_repo_hour", new_logs.size
        end
      end
    end
    owners_activity
  end

  def save_owner_activities(activities)
    txn_count = 0
    activities.each do |owner_id, owner_activities|
      actor_ids = Set.new
      key_ids = Set.new

      owner_activities[:repos].each_slice(TXN_SIZE) do |items|
        Asset::ActorActivity.throttle do
          # Note that this works because Asset::ActorActivity and
          # Asset::Activity are both on mysql1.
          Asset::ActorActivity.transaction do
            items.each do |repo_id, times|
              times.each do |started_at, actors|
                total = T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))
                actors.each do |(actor_id, key_id), actor_items|
                  if total.nil?
                    total = actor_items
                  else
                    total[:up] += actor_items[:up]
                    total[:down] += actor_items[:down]
                    total[:files] += actor_items[:files]
                  end

                  Asset::ActorActivity.track(:lfs, owner_id, actor_id, key_id, repo_id, started_at,
                                             up: actor_items[:up],
                                             down: actor_items[:down])
                  actor_ids << actor_id
                  key_ids << key_id
                end

                # We know total is non-nil if there's at least one actor, which
                # there always will be (or we wouldn't have created the entry).
                total = T.must(total)

                T.cast(total[:files], T::Array[String]).uniq!

                seen_files = Asset::Activity.seen_source_files(:lfs, owner_id, repo_id, started_at)
                dup_files = T.cast(total[:files], T::Array[String]) & Array(seen_files)
                if dup_files.any?
                  stat_incr "transaction_rollback"
                  raise ActiveRecord::Rollback
                end

                Asset::Activity.track(:lfs, owner_id, repo_id, started_at,
                                      up: total[:up],
                                      down: total[:down],
                                      source_files: total[:files]
                                     )
              end
            end
          end
          stat_gauge "transaction_size", items.size
          txn_count += 1
        end
      end

      RebuildStorageUsageJob.perform_later(owner_id, { "notify" => true, "asset_type" => "lfs",
        "actor_ids" => actor_ids.to_a, "key_ids" => key_ids.to_a })
    end
    stat_gauge "transaction_count", txn_count
  rescue Freno::Throttler::Error => err
    stat_incr "throttler_error_retry"
    raise err
  end

  def emit_owner_activities(activities)
    organization_ids = activities.map { |_owner_id, owner_activities| owner_activities[:organization_id] }.compact.uniq
    organizations = Organization.where(id: organization_ids).index_by(&:id)

    customer_ids = activities.map { |_owner_id, owner_activities| owner_activities[:customer_id] }.compact.uniq
    customers = Customer.where(id: customer_ids).index_by(&:id)

    activities.each do |_owner_id, owner_activities|
      customer_id = owner_activities[:customer_id]
      organization_id = owner_activities[:organization_id]
      business_id = owner_activities[:business_id]
      org = organizations[organization_id]
      owner_activities[:repos].each do |repo_id, times|
        times.each do |started_at, actors|
          actors.each do |(actor_id, _key_id), actor_items|
            emit_download_bandwidth_usage(
              customer_id: customer_id,
              actor_id: actor_id,
              repo_id: repo_id,
              organization_id: organization_id,
              usage_at: started_at,
              size_in_gb: actor_items[:down]
            )
          end
        end
      end
    end
  end

  def emit_download_bandwidth_usage(customer_id:, actor_id:, organization_id:, repo_id:, usage_at:, size_in_gb:)
    return if size_in_gb <= 0

    GlobalInstrumenter.instrument("billing_platform.metered_usage", {
      sku: "git_lfs_bandwidth",
      quantity: size_in_gb,
      usage_at:  Google::Protobuf::Timestamp.new(seconds: usage_at.to_i, nanos: 0),
      source_uri: "gid://git-hub/Repository/#{repo_id}",
      entity: {
        customer_id: customer_id,
        repo_id: repo_id,
        organization_id: organization_id,
        actor_id: actor_id,
      },
    })
  end

  def parse_line(line)
    return unless line
    query_params = line[:query]
    raw_line = line[:raw]
    method = line[:method]
    parsed_info = line.dup

    parsed_info[:network_id] = key_to_network_id(raw_line.key)
    return if parsed_info[:network_id].nil?

    # NOTE: Requests without any query arguments are made by AWS S3 replication tasks,
    #       and should not be billed to customers.
    return if query_params["actor_id"].nil? && query_params["key_id"].nil? && query_params["repo_id"].nil?

    parsed_info[:actor_id] = first_int_parameter(query_params["actor_id"])
    parsed_info[:key_id] = first_int_parameter(query_params["key_id"])
    parsed_info[:repo_id] = first_int_parameter(query_params["repo_id"])

    bytes_sent = raw_line.bytes_sent.to_f
    object_size = raw_line.object_size.to_f
    parsed_info[:response_time] = raw_line.total_time.to_i
    case method
    when "GET"
      parsed_info[:bandwidth_down] = bytes_sent / GIGABYTE
    when "PUT"
      parsed_info[:bandwidth_up] = object_size / GIGABYTE
    end
    parsed_info
  end

  def first_int_parameter(val)
    # If there is more than one query param, we want the first one
    case id = val
    when Array # If we get more than one query param, we want the first
      id[0].to_i
    when String # If we only get back 1 query param,
      id.to_i
    when nil
      0
    end
  end

  def key_to_network_id(key)
    parts = key.split("/").reject(&:empty?)
    return unless parts.size > 2
    network_id = parts[2].to_i
    return unless network_id.positive?
    network_id
  end
end
