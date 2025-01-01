# typed: false
# frozen_string_literal: true

require "set"
require "logger"
require "github/pages/management/add_replica"
require "github/pages/management/add_replica_azure"

module GitHub::Pages::Management
  class Repair
    class ReplicationInfo

      attr_reader :page_id, :page_deployment_id, :replica_count_by_datacenter, :voting

      def initialize(page_id, page_deployment_id, replica_count_by_datacenter, voting)
        @page_id, @page_deployment_id, @replica_count_by_datacenter, @voting =
          page_id, page_deployment_id, replica_count_by_datacenter, voting
        nil
      end

      def replica_count
        replica_count_by_datacenter.values.sum
      end
    end

    SQL_BATCH_SIZE = 5_000


    attr_reader :delegate, :missing_replicas

    def initialize(delegate:)
      @delegate = delegate
      nil
    end

    def repair_azure_site?
      return false if GitHub.enterprise?
      GitHub.flipper[:pages_azure_dfs_host].enabled?
    end

    def perform
      delegate.log "Finding pages sites with fewer than required replicas..."

      # Collect all sites which need repair, starting with those with fewer replica counts.
      to_be_repaired = repairable_unhealthy_pages_replica_counts

      delegate.log "Found #{to_be_repaired.count} sites needing replica repair"

      succeeded = true

      to_be_repaired.each_with_index do |repl, index|
        delegate.log "Repairing page_id=#{repl.page_id} page_deployment_id=#{repl.page_deployment_id.inspect} (completed #{index} of #{to_be_repaired.count})"
        if repair_azure_site?
          if !repair_single_site_azure(page_id: repl.page_id, page_deployment_id: repl.page_deployment_id)
            succeeded = false
          end
        else
          if !repair_single_site(page_id: repl.page_id, page_deployment_id: repl.page_deployment_id, voting: repl.voting, replica_count_by_datacenter: repl.replica_count_by_datacenter)
            succeeded = false
          end
        end
      end

      succeeded
    end

    # All sites that need to be repaired which are repairable.
    def repairable_unhealthy_pages_replica_counts(limit: nil)
      processed_count = 0

      # Unhealthy replica counts are fetched in batches; they are filtered here
      # to exclude sites that can't be repaired.
      replica_counts = unhealthy_pages_replica_counts(limit: limit) do |batch|
        GitHub.dogstats.increment("pages.dpages_repair.batch_count")
        unrepairable = batch.each_with_object({}) do |repl, memo|
          if repl.voting && repl.replica_count == 0
            (memo[repl.page_id] ||= {})[repl.page_deployment_id] = true
          end
        end
        filtered_results = batch.select { |repl| repairable?(repl, unrepairable) }
        GitHub.dogstats.count("pages.dpages_repair.filtered_batch_count", filtered_results.size)

        # Caller may elect to process results from each batch vs waiting for all batches.
        #
        # We need to track the number of sites we've yielded to the caller to ensure it doesn't
        # go over the limit.
        if block_given?
          count_to_process = limit.present? ? limit - processed_count : filtered_results.size
          count_to_process = [count_to_process, filtered_results.size].min
          filtered_results.first(count_to_process).each { |result| yield result }
          processed_count += count_to_process
        end

        filtered_results
      end

      GitHub.dogstats.gauge("pages.dpages_repair.repairable_unhealthy_count", replica_counts.size)

      replica_counts
    end

    # Determine if a ReplicationInfo can be repaired.
    # If a repair has 0 voting replicas, then it cannot be performed, so do not attempt it.
    #
    # repl - a GitHub::Pages::Management::Replair::ReplicationInfo
    # unrepairable - A Hash of ` { page_id => { page_deployment_id => true } }` where a
    #                true value indicates that the page_id/page_deployment_id pair has no
    #                voting replicas from which to repair.
    #
    # Returns true if the repair should be performed, false otherwise.
    def repairable?(repl, unrepairable)
      if repl.voting
        # You can't create voting replicas out of thin air.
        return false if repl.replica_count == 0
      else
        # You can't replicate non-voting replicas when no voting replicas exist.
        u = unrepairable[repl.page_id]
        return false if u && u[repl.page_deployment_id]
      end

      true
    end

    # Fetch all unhealthy replica counts. Optionally pass a block to filter.
    #
    # limit - nil or a number greater than 0. Caps the results array size.
    # block - (optional) Pass a block which will be used to filter the results.
    #         It is passed the intermediate results set & should filter them.
    #         It should return a filtered set of results.
    def unhealthy_pages_replica_counts(limit: nil)
      unhealthy_hosts = unhealthy_pages_hosts_in_pages_replicas

      lower_bound = 0

      results = []

      loop do
        upper_bound = ApplicationRecord::Pages.connection.select_value(Arel.sql(<<-SQL, lower_bound: lower_bound, batch_size: Arel.sql(SQL_BATCH_SIZE.to_s)))
          SELECT MAX(id) FROM (
            SELECT id FROM pages WHERE id > :lower_bound LIMIT :batch_size
          ) t
        SQL

        break unless upper_bound

        # Returns an array of page_ids
        # Example:
        #   [324, 325, 328, 329]
        pages_ids = ApplicationRecord::Pages.connection.select_values(Arel.sql(<<-SQL, lower_bound: lower_bound, upper_bound: upper_bound))
          SELECT pages.id as page_id
            FROM pages
           WHERE pages.id > :lower_bound
             AND pages.id <= :upper_bound
        SQL

        if pages_ids.empty?
          lower_bound = upper_bound
          next
        end

        # A unique selection of [page_id, page_deployment_id] pairs representing one deployed site.
        # This is the master list of all sites that should be deployed.
        # Returns a set
        # Example:
        #   <Set: {[328, 58], [324, nil], [325, nil], [329, nil]}>
        page_and_page_deployment_ids = page_deployment_ids_for_page_id_range(
          offset: lower_bound,
          next_offset: upper_bound,
        )

        # Voting replicas counts must be grouped by datacenter so we can verify multisite replication strategy
        # Returns a tuple of replicas with page_id, deployment_id, datacenter, and number of replicas in that datacenter
        # Example:
        #   [[327, 57, "ac4", 1], [328, 58, "va3", 2]]

        exclude_hosts = unhealthy_hosts
        if !repair_azure_site?
          exclude_hosts += all_non_voting_hosts
        end

        replicas = pages_replica_counts_for_page_id_range(
          offset:        lower_bound,
          next_offset:   upper_bound,
          exclude_hosts: exclude_hosts,
          by_datacenter: true,
        )

        # Create a batch of replicas to work on
        # Returns an array of GitHub::Pages::Management::Repair::ReplicationInfo
        # Example:
        #   @page_deployment_id=58,
        #   @page_id=328,
        #   @replica_count_by_datacenter={"ash1"=>2},
        #   @voting=true>
        batch =
        if repair_azure_site?
          fill_out_replica_counts(
            counts:        replicas,
            ids:           page_and_page_deployment_ids.to_a,
            target_copies: GitHub.pages_azure_replica_count,
            voting:        true,
          )
        else
          result = fill_out_replica_counts(
            counts:        replicas,
            ids:           page_and_page_deployment_ids.to_a,
            target_copies: GitHub.pages_replica_count,
            voting:        true,
          )

          # if we have online non-voting hosts
          if !GitHub.pages_non_voting_replica_count.nil? && !healthy_non_voting_hosts.empty?
            non_voting_replicas = pages_replica_counts_for_page_id_range(
              offset:        lower_bound,
              next_offset:   upper_bound,
              include_hosts: healthy_non_voting_hosts,
            )

            result.concat(fill_out_replica_counts(
              counts:        non_voting_replicas,
              ids:           page_and_page_deployment_ids.to_a,
              target_copies: GitHub.pages_non_voting_replica_count,
              voting:        false,
            ))
          end
          result
        end

        lower_bound = upper_bound

        # Allow consumers of this API to filter this batch based on a block.
        if block_given?
          batch = yield batch
        end

        results.concat(batch)

        # Allow callers to limit the number of results returned.
        if (limit_ = limit) && limit_ <= results.size
          return results.take(limit_)
        end
      end

      results
    end

    def pages_replica_counts_for_page_id_range(offset:, next_offset:, exclude_hosts: [], include_hosts: [], by_datacenter: false)
      columns = %w(page_id pages_deployment_id).tap do |cols|
        cols << (by_datacenter ? "pf.datacenter" : "NULL as datacenter")
      end

      sql = Arel.sql "SELECT #{columns.join(", ")} FROM"

      # Use a derived table in case we need to join to pages_fileservers to get the datacenter
      sql += Arel.sql(<<-SQL, offset: offset, next_offset: next_offset)
        (
          SELECT host,
                 pages_deployment_id,
                 page_id
          FROM   pages_replicas USE INDEX (index_pages_replicas_on_page_id_and_pages_deployment_id_and_host)
          WHERE  page_id > :offset AND page_id <= :next_offset
      SQL
      sql += Arel.sql "AND host NOT IN (:bad_hosts)", bad_hosts: exclude_hosts unless exclude_hosts.empty?
      sql += Arel.sql "AND host IN (:good_hosts)", good_hosts: include_hosts unless include_hosts.empty?
      sql += Arel.sql(") pr")

      if by_datacenter
        sql += Arel.sql("JOIN pages_fileservers pf on pr.host = pf.host")
      end
      # Group and count number of records in Ruby to avoid a GROUP BY across multiple tables
      ApplicationRecord::Pages.connection.select_rows(sql)
        .group_by(&:itself)
        .map do |columns, records|
          [*columns, records.size]
        end
    end

    # This helps build a master list of (page_id,page_deployment_id) pairs.
    # In order to consider a site deployed, it must have a revision.
    # In the case of nil page_deployment_id's then we need to check pages.built_revison,
    # since there's no revision in page_deployments. If a record does exist,
    # then it's only deployed if a revision exists. Check the validity of
    # the revision based on the presence or absence of page_deployment_id.
    #
    # If page_deployments.id is NULL, then pages.built_revision must exist.
    # If page_deployments.id IS NOT NULL, then page_deployments.revision must exist.
    def page_deployment_ids_for_page_id_range(offset:, next_offset:)
      ApplicationRecord::Pages.connection.select_rows(Arel.sql(<<-SQL, offset: offset, next_offset: next_offset)).to_set
        SELECT
          pages.id as page_id,
          page_deployments.id as page_deployment_id
        FROM pages
        LEFT OUTER JOIN page_deployments ON (page_deployments.page_id = pages.id)
        WHERE pages.id > :offset
          AND pages.id <= :next_offset
          AND (
            (page_deployments.id IS NULL AND pages.built_revision IS NOT NULL)
            OR
            (page_deployments.id IS NOT NULL AND page_deployments.revision IS NOT NULL)
          )
      SQL
    end

    # Condense the counts from the database down to the counts that need action.
    #
    # - counts is an array of tuples. Each tuple is [page_id, page_deployment_id, datacenter, replica_count].
    # - ids is an array of [page_id, page_deployment_id] tuples that should be present in counts.
    # - target_copies is the right number of replicas.
    # - voting is a boolean, whether the counts are for voting replicas or not.
    def fill_out_replica_counts(counts:, ids:, target_copies:, voting:)
      # Group counts by [page_id, deployment_id]
      results = counts.each_with_object({}) do |(id, deployment_id, datacenter, copies), grouped|
        tuple = [id, deployment_id]
        grouped[tuple] ||= {}
        grouped[tuple][datacenter] = copies
      end

      # No replicas.
      ids.each { |tuple| results[tuple] = { nil => 0 } unless results.key?(tuple) }

      # Remove anything that has the right number of replicas.
      results.delete_if do |(page_id, page_deployment_id), counts_by_datacenter|
        !is_missing_replicas?(page_id: page_id, page_deployment_id: page_deployment_id, counts_by_datacenter: counts_by_datacenter, target_copies: target_copies, voting: voting)
      end

      # ReplicationInfo sorted by number of copies
      results.map do |(page_id, page_deployment_id), counts_by_datacenter|
        ReplicationInfo.new(page_id, page_deployment_id, counts_by_datacenter, voting)
      end.select do |repl|
        ids.include?([repl.page_id, repl.page_deployment_id])
      end.sort_by! do |repl|
        [repl.replica_count, repl.page_id, repl.page_deployment_id]
      end
    end

    def is_missing_replicas?(page_id:, page_deployment_id:, counts_by_datacenter:, target_copies:, voting:)
      if repair_azure_site?
        counts_by_datacenter.values.sum < target_copies
      elsif voting && replication_strategy.is_a?(GitHub::Pages::ReplicationStrategy)
        missing_replicas = replication_strategy.missing_replica_counts(
          page_id: page_id,
          page_deployment_id: page_deployment_id,
          healthy_replica_counts: counts_by_datacenter,
        )
        missing_replicas.any? { |_datacenter, needed_count| needed_count > 0 }
      else
        counts_by_datacenter.values.sum < target_copies
      end
    end

    def offline_hosts
      @offline_hosts ||= ApplicationRecord::Pages.connection.select_values(<<-SQL)
        SELECT host FROM pages_fileservers WHERE online = 0
      SQL
    end

    # Find all hosts that are non-voting.
    def all_non_voting_hosts
      @non_voting_pages_hosts ||= ApplicationRecord::Pages.connection.select_values(<<-SQL)
        SELECT host FROM pages_fileservers WHERE non_voting = 1
        ORDER BY host ASC
      SQL
    end

    def healthy_voting_hosts
      @voting_pages_hosts ||= ApplicationRecord::Pages.connection.select_values(<<-SQL)
        SELECT host FROM pages_fileservers WHERE non_voting = 0 AND online = 1
        ORDER BY host ASC
      SQL
    end

    def healthy_non_voting_hosts
      @non_voting_pages_hosts ||= ApplicationRecord::Pages.connection.select_values(<<-SQL)
        SELECT host FROM pages_fileservers WHERE non_voting = 1 AND online = 1
        ORDER BY host ASC
      SQL
    end

    def unhealthy_pages_hosts_in_pages_replicas
      sql = <<-SQL
        SELECT sub.host, fs.datacenter
          FROM (
            SELECT DISTINCT host FROM pages_replicas
          ) sub
          LEFT JOIN pages_fileservers fs ON sub.host = fs.host
          WHERE IFNULL(fs.online, 0) != 1
      SQL
      ApplicationRecord::Pages.connection.select_values(sql)
    end

    def remove_offline_replicas(page_id:, page_deployment_id:, offline_hosts:, delegate:)
      return true unless offline_hosts
      return true if offline_hosts.empty?

      affected_rows = if page_deployment_id
        ApplicationRecord::Pages.connection.delete(Arel.sql(<<-SQL, page_id: page_id, page_deployment_id: page_deployment_id, offline_hosts: offline_hosts))
          DELETE FROM pages_replicas WHERE page_id = :page_id AND pages_deployment_id = :page_deployment_id AND host IN (:offline_hosts)
        SQL
      else
        ApplicationRecord::Pages.connection.delete(Arel.sql(<<-SQL, page_id: page_id, offline_hosts: offline_hosts))
          DELETE FROM pages_replicas WHERE page_id = :page_id AND pages_deployment_id IS NULL AND host IN (:offline_hosts)
        SQL
      end

      if affected_rows > 0
        delegate.log "Removed #{affected_rows} replicas of page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect} " \
          "on hosts=#{offline_hosts.join(",")}"
      else
        delegate.log "Did not remove any replicas for page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect} " \
          "on hosts=#{offline_hosts.join(",")}"
      end

      true
    end

    def repair_single_site_azure(page_id:, page_deployment_id:)

      # this is a hash of datacenter mapping to hosts. e.g.
      # { "azureeastus1" => "host1,host2" }
      datacenters_with_hosts = counts_per_site_azure(page_id: page_id, page_deployment_id: page_deployment_id).to_h
      datacenters_with_hosts.default = ""

      replica_to_repair = []

      # get missing replicas that are offline
      exclude_hosts = offline_hosts

      # in format {"azureeastus1"=>1, "azureeastus2"=>1, "azureeastus3"=>1}
      required_replicas_per_datacenter = GitHub.pages_dfs_datacenters.zip(GitHub.pages_replica_count_per_datacenters).to_h
      required_replicas_per_datacenter.default = 0

      required_replicas_per_datacenter.each do |datacenter, ammount|
        current_hosts = datacenters_with_hosts[datacenter].split(",")

        # if current hosts exclude offline hosts is not equal to current hosts, then we have missing replicas in this datacenter
        missing_count = ammount - (current_hosts - exclude_hosts).length
        if missing_count > 0
          replica_to_repair << [datacenter, missing_count]
        end
      end

      return nil unless replica_to_repair.any?

      succeeded = true

      if GitHub.multi_tenant_enterprise?
        client = Page::Twirp::RequestClient.new(service_name: "repair")
        client.update_replica(page_id: page_id, deployment_id: page_deployment_id, replica_to_add: [], replica_to_remove: exclude_hosts)
      end

      replica_to_repair.each do |data_center, missing_count|
        missing_count.times do
          unless AddReplicaAzure.new(page_id: page_id, page_deployment_id: page_deployment_id, delegate: delegate, data_center: data_center).perform
            succeeded = false
            break
          end
        end
        break unless succeeded

        unless remove_offline_replicas(page_id: page_id, page_deployment_id: page_deployment_id, offline_hosts: exclude_hosts, delegate: delegate)
          succeeded = false
          break
        end
      end

      status = succeeded ? "success" : "failure"
      GitHub.dogstats.increment("pages.management.repair.sites_repaired", tags: ["status:#{status}"])

      succeeded
    end

    def repair_single_site(page_id:, page_deployment_id:, voting:, replica_count_by_datacenter: nil)
      # If we're deploying with a multi-site replication strategy, figure out which data centers need replicas
      strategy = replication_strategy
      if voting && strategy.is_a?(GitHub::Pages::ReplicationStrategy)
        missing_replicas = strategy.missing_replica_counts(page_id: page_id, page_deployment_id: page_deployment_id, healthy_replica_counts: replica_count_by_datacenter)
        delegate.log({ "message": "Missing voting Replicas for page_id: #{page_id}", "page_id": "#{page_id}", "page_deployment_id": "#{page_deployment_id}", "missing_replicas": "#{missing_replicas}", "voting": "#{voting}" })
      else
        strategy = "none"
        target_replica_count = voting ? GitHub.pages_replica_count : GitHub.pages_non_voting_replica_count
        actual_replica_count = if replica_count_by_datacenter.present?
          if GitHub.datacenter == GitHub.default_datacenter
            replica_count_by_datacenter.values.sum
          else
            replica_count_by_datacenter[GitHub.datacenter] || 0
          end
        else
          count_for_single_site(page_id: page_id, page_deployment_id: page_deployment_id, voting: voting)
        end

        needed_replica_count = target_replica_count.to_i - actual_replica_count

        missing_replicas = { GitHub.datacenter => needed_replica_count }

        voting_bit = voting ? "voting" : "non-voting"
        delegate.log({ "message": "Missing #{voting_bit} Replicas for page_id: #{page_id}", "page_id": "#{page_id}", "page_deployment_id": "#{page_deployment_id}", "missing_replicas": "#{missing_replicas}", "voting": "#{voting}" })
      end

      return nil unless missing_replicas.detect { |_, count| count > 0 }

      succeeded = true

      missing_replicas.each do |data_center, needed|
        needed.times do
          if !AddReplica.new(page_id: page_id, page_deployment_id: page_deployment_id, delegate: delegate, voting: voting, data_center: data_center).perform ||
            !remove_offline_replicas(page_id: page_id, page_deployment_id: page_deployment_id, offline_hosts: offline_hosts, delegate: delegate)
            succeeded = false
          end
        end
      end

      stat_bit = succeeded ? "success" : "failure"
      GitHub.dogstats.increment("pages.management.repair.sites_repaired", tags: ["status:#{stat_bit}", "voting:#{voting}", "strategy:#{strategy}"])
      GitHub.stats.increment("pages.management.repair.sites_repaired.#{stat_bit}") if GitHub.enterprise?

      succeeded
    end

    def count_for_single_site(page_id:, page_deployment_id:, voting:)
      hosts = voting ? healthy_voting_hosts : healthy_non_voting_hosts

      sql_bindings = {
        page_id: page_id,
        page_deployment_id: page_deployment_id,
        hosts: hosts,
      }
      sql = Arel.sql(<<-SQL, **sql_bindings)
        SELECT
          COUNT(host) as copies
        FROM pages_replicas
        WHERE page_id = :page_id
      SQL
      sql += Arel.sql("AND pages_deployment_id IS NULL") if page_deployment_id.nil?
      sql += Arel.sql("AND pages_deployment_id = :page_deployment_id", **sql_bindings) unless page_deployment_id.nil?
      sql += Arel.sql("AND host NOT IN (:exclude_hosts)", exclude_hosts: unhealthy_pages_hosts_in_pages_replicas + all_non_voting_hosts) if voting
      sql += Arel.sql("AND host IN (:include_hosts)", include_hosts: healthy_non_voting_hosts) unless voting

      ApplicationRecord::Pages.connection.select_value(sql)
    end

    def counts_per_site_azure(page_id:, page_deployment_id:)
      sql_bindings = {
        page_id: page_id,
        page_deployment_id: page_deployment_id,
      }

      sql = Arel.sql(<<-SQL, **sql_bindings)
        SELECT
        pages_fileservers.datacenter, GROUP_CONCAT(pages_fileservers.host ORDER BY pages_fileservers.host ASC) as hosts
        FROM pages_replicas
        INNER JOIN pages_fileservers ON pages_fileservers.host = pages_replicas.host
        WHERE pages_replicas.page_id = :page_id
      SQL
      sql += Arel.sql("AND pages_replicas.pages_deployment_id IS NULL") if page_deployment_id.nil?
      sql += Arel.sql("AND pages_replicas.pages_deployment_id = :page_deployment_id", **sql_bindings) unless page_deployment_id.nil?
      sql += Arel.sql("GROUP BY pages_fileservers.datacenter")

      ApplicationRecord::Pages.connection.select_rows(sql)
    end

    def replication_strategy
      return nil if GitHub.enterprise?
      GitHub.pages_replication_strategy
    end
  end
end
