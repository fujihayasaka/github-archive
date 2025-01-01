# typed: true
# frozen_string_literal: true

# This class defines a strategy for replicating a Pages site to a specified number of hosts
# distributed across data centers.
class GitHub::Pages::ReplicationStrategy
  attr_reader :data_centers, :replica_counts

  def initialize(data_centers: nil, replica_counts: nil)
    @data_centers = Array(data_centers)
    @data_centers << GitHub.datacenter if @data_centers.empty?

    @replica_counts = Array(replica_counts)
    @replica_counts << GitHub.pages_replica_count if @replica_counts.empty?
  end

  def to_s
    "#{replica_counts.join("_")}-#{data_centers.join("_")}"
  end

  def distribute
    distribution = Hash[data_centers.shuffle.zip(replica_counts.cycle)]
    distribution.inject([]) do |hosts, (data_center, replica_count)|
      new_hosts = yield data_center, replica_count
      hosts += new_hosts
    end
  end

  def missing_replica_counts(page_id:, page_deployment_id:, healthy_replica_counts: nil)
    healthy_replica_counts ||= begin
      required_datacenters = (data_centers - [GitHub.default_datacenter]).compact
      healthy_counts_bindings = {
        page_id: page_id,
        page_deployment_id: page_deployment_id,
        data_centers: required_datacenters,
      }
      healthy_counts = Arel.sql(<<-SQL, **healthy_counts_bindings)
        SELECT pf.datacenter, count(pr.host) AS count
        FROM pages_replicas pr
          JOIN pages_fileservers pf ON pr.host = pf.host
        WHERE pr.page_id = :page_id
          AND pf.online = 1 AND pf.embargoed = 0 AND pf.non_voting = 0
      SQL
      healthy_counts += Arel.sql("AND pf.datacenter IN (:data_centers)", **healthy_counts_bindings) unless required_datacenters.empty?
      healthy_counts += Arel.sql("AND pr.pages_deployment_id = :page_deployment_id", **healthy_counts_bindings) unless page_deployment_id.nil?
      healthy_counts += Arel.sql("GROUP BY pf.datacenter")

      ApplicationRecord::Domain::PagesFromRepositories.connection.select_rows(healthy_counts).inject({}) do |counts, (datacenter, count)|
        datacenter ||= GitHub.default_datacenter
        counts.merge!(datacenter => count)
      end
    end

    existing_data_centers = healthy_replica_counts.keys.sort_by { |key| -(healthy_replica_counts[key]) }
    missing_data_centers = (data_centers - existing_data_centers).shuffle

    # remove any data centers that aren't part of the strategy
    required_existing_data_centers = existing_data_centers.select { |dc| data_centers.include?(dc) }

    missing_replicas = {}

    # replica_counts is an array that represents the number of replicas we need in each datacenter
    # (e.g. 2-2-1)
    replica_counts.sort.reverse.each_with_index do |needed_count, i|
      checked_data_center = required_existing_data_centers[i] || missing_data_centers.pop unless missing_data_centers.nil?
      return unless checked_data_center

      if healthy_replica_counts[checked_data_center].nil?
        # If there are no replicas in this datacenter
        # Use needed_count since we can pull a replica from another online host
        missing_replicas[checked_data_center] = needed_count
      elsif required_existing_data_centers[i] == checked_data_center
        # If there are existing replicas in this datacenter,
        # calculate how many is left to satisfy the strategy
        existing_count = healthy_replica_counts[checked_data_center]
        missing_replicas[checked_data_center] = needed_count - existing_count
      end
    end
    missing_replicas
  end
end
