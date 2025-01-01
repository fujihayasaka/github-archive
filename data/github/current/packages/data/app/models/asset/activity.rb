# typed: true
# frozen_string_literal: true

# Represents an owner's asset activity broken down by owner, resource, and hour.
# Note that hours with no access activity will not count any byte hours.
class Asset::Activity < ApplicationRecord::Domain::Assets
  include Asset::Types


  self.table_name = :asset_activities

  belongs_to :owner, class_name: "User"

  # This may be nil (ID 0) for older data which was not stored on a
  # per-repository basis.
  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain

  # Public: Increase the bandwidth and byte hours for an owner's data for a
  # given hour (as defined by started_at).
  def self.track(asset_type, owner_id, repo_id, started_at, up: nil, down: nil, source_files: nil)
    up = up.to_f
    down = down.to_f
    return unless up > 0.0 || down > 0.0
    return if asset_type == :lfs && repo_id.to_i == 0

    uniq_src_files = Array(source_files).delete_if(&:blank?).uniq
    return if uniq_src_files.blank?

    bindings = {
      owner_id: owner_id,
      repository_id: repo_id,
      # Remove millis from "started_at" so MySQL won't round up to the next second.
      # This makes sure that objects are not "started in the future", which  will confuse
      # a few tests.
      started_at: started_at.floor,
      down: down,
      up: up,
      files: encode_source_lines(uniq_src_files, 65535),
      asset_type: self.asset_types[asset_type],
    }

    q = <<-SQL
      INSERT INTO asset_activities (
        owner_id, repository_id, activity_started_at,
        bandwidth_down, bandwidth_up, source_files, asset_type,
        created_at, updated_at
      ) VALUES (
        :owner_id, :repository_id, :started_at,
        :down, :up, :files, :asset_type,
        NOW(), NOW()
      ) ON DUPLICATE KEY UPDATE
        bandwidth_down = bandwidth_down+VALUES(bandwidth_down),
        bandwidth_up = bandwidth_up+VALUES(bandwidth_up),
        source_files = RIGHT(CONCAT_WS(',', NULLIF(source_files, ''), NULLIF(VALUES(source_files), '')), 65535),
        updated_at = NOW()
    SQL

    ActiveRecord::Base.connected_to(role: :writing) do
      self.connection.insert(Arel.sql(q, **bindings))
    end

    GitHub.dogstats.increment("s3_usage.activities",
      tags: ["type:#{asset_type}"],
    )
  end

  def self.encode_source_lines(lines, col_limit)
    s = Array(lines).join(",")
    s.gsub!(/\,{2,}/, ",") # remove dup commas
    s.gsub!(/\A,/, "")
    s.gsub!(/,\z/, "")
    if s.size > col_limit
      s = s[s.size - col_limit..-1]
    end
    s
  end

  # Finds all Asset::Activities from a single owner over a time period, bucketed
  # to the hour.
  def self.fetch_for_owner(asset_type, owner, from, to)
    Asset::Activity.
      where(owner_id: owner.id, asset_type: Asset::Activity.asset_types[asset_type]).
      where("activity_started_at >= ? AND activity_started_at < ?", from, to)
  end

  # Computes all activity from a single owner over a time period, bucketed by
  # network ID.
  def self.fetch_for_owner_by_network(asset_type, owner_id, from, to)
    ActiveRecord::Base.connected_to(role: :reading) do
      # First, let's find all repository IDs for this time randge and owner.
      all_repo_ids = Asset::Activity.
        where("activity_started_at >= ? AND activity_started_at < ?", from, to).
        where(
          asset_type: Asset::Activity.asset_types[asset_type],
          owner_id: owner_id,
      ).distinct.pluck(:repository_id)

      # Let's map each repository ID to its corresponding network ID.  For
      # historical reasons, the latter is called "source_id" in the database.
      repos = Repository.where(id: all_repo_ids).pluck(:id, :source_id).to_h

      # Group our repositories by network.  That is, create a map mapping a
      # network ID to an Array of repository IDs in that network.
      grouped_networks = all_repo_ids.group_by { |id| repos[id] }

      # For each network ID, look up the sums of the bandwidth up and down for
      # its repositories.  Produce a map that maps the network ID to a hash with
      # the bandwidth_up and bandwidth_down keys.
      grouped_networks.map do |(net_id, repo_ids)|
        result = Asset::Activity.
          where("activity_started_at >= ? AND activity_started_at < ?", from, to).
          where(
            asset_type: Asset::Activity.asset_types[asset_type],
            owner_id: owner_id,
            repository_id: repo_ids,
            ).select("SUM(asset_activities.bandwidth_up) as bandwidth_up, SUM(asset_activities.bandwidth_down) as bandwidth_down")

        # We should always receive a single list with the two sum values.
        next if result.length != 1

        [
          net_id,
          {
            bandwidth_up: result[0].bandwidth_up,
            bandwidth_down: result[0].bandwidth_down,
          },
        ]
      end.compact.to_h
    end
  end

  def self.seen_source_files(asset_type, owner_id, repo_id, started_at)
    source_files = Asset::Activity.where(
      asset_type: Asset::Activity.asset_types[asset_type],
      owner_id: owner_id,
      repository_id: repo_id,
      activity_started_at: started_at,
    ).limit(1).pluck(:source_files)

    return Set.new if source_files.empty?

    ids = source_files[0].to_s.split(",")
    ids.uniq!
    Set.new(ids.delete_if { |id| id.blank? })
  end

  def self.fetch_or_create_customer_id(billable_owner)
    if billable_owner.delegate_billing_to_business?
      return billable_owner.business.customer_id
    end

    customer = billable_owner.customer
    if customer
      return customer.id
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      new_customer = Billing::CreateCustomer.perform(billable_owner).customer

      GitHub.dogstats.increment(
        "billing.resolve_billable_owner.create_customer.count",
        tags: ["success:#{new_customer.present?}", "created_via_asset:true"],
      )

      new_customer.id
    end
  end

end
