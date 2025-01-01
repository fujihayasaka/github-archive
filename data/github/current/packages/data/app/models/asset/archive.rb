# typed: true
# frozen_string_literal: true

# Keeps a reference around to an asset that has been deleted.  A periodic job
# runs to ensure this cleans up old assets after the expiration period.
class Asset::Archive < ApplicationRecord::Domain::Assets

  include Asset::AlambicCaller
  class PurgeError < StandardError
  end

  belongs_to :asset

  def self.deletable_since(oldest_time, limit: nil)
    # uses the `created_at` index.  It may result in duplicate records, but
    # the delete requests are idempotent, so it doesn't matter.
    cond = ["created_at <= ?", oldest_time]
    where(cond).order("created_at asc").limit(limit || 100)
  end

  def self.all_deleteable(ids)
    ids = Array(ids)
    ids.uniq!
    ids = ids.first(100)

    includes(:asset).where(id: ids).select(&:delete?)
  end

  def self.purge(ids)
    ids = Array(ids)
    ids.flatten!
    ids.uniq!
    return if ids.blank?
    ids = ids.first(100)

    res = http.delete("/assets/purge") do |req|
      json = { ids: ids }.to_json
      req.headers.update(
        "Content-Type" => "application/json",
        "Content-HMAC" => Api::Internal.content_hmac(json),
      )
      req.body = json
    end

    if res.status != 200
      raise PurgeError, "Unsuccessful response: #{res.status}"
    end

    body = JSON.parse(res.body)
    return if body.blank?

    oids = []
    index = {} # string oid => [string path_prefix, path_prefix, ...]
    body.each do |h|
      oids << oid = h["oid"]
      (index[oid] ||= Set.new) << h["path_prefix"]
    end

    assets = ActiveRecord::Base.connected_to(role: :reading) { Asset.where(oid: oids).all }
    purged = assets.select do |asset|
      next unless path_prefixes = index[asset.oid]
      archives = ActiveRecord::Base.connected_to(role: :reading) do
        Asset::Archive.where(asset_id: asset.id, path_prefix: path_prefixes.to_a)
      end

      asset.purge!(archives)
    end

    unpurged = assets.size - purged.size

    GitHub.dogstats.count("archived_files.purged", purged.size)
    GitHub.dogstats.count("archived_files.kept", unpurged)

    unpurged == 0
  end

  # An archive never archives itself.
  def archive?(*args)
    false
  end

  # Implemented for AssetUploadable.  Other uploadable records generate the
  # alambic_path_prefix.  Asset::Archive stores it in the `path_prefix` field.
  def alambic_path_prefix
    path_prefix.present? ? path_prefix : GitHub.alambic_path_prefix
  end

  def delete?
    asset_oid && (Time.now - expiration_period) > T.cast(created_at, T.untyped)
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def asset_oid
    @asset_oid ||= asset&.oid
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def purge
    return unless delete?
    self.class.purge(id)
  end

  def self.stub_purge(&block)
    stub_http do |stub|
      stub.delete("/assets/purge", &block)
    end
  end

  def self.expiration_period
    ::RepositoryBulkPurgeJob.expiration_period
  end

  private

  def expiration_period
    ::RepositoryBulkPurgeJob.expiration_period
  end
end
