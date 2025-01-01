# typed: true
# frozen_string_literal: true

class Storage::Blob < ApplicationRecord::Domain::Storage
  self.table_name = :storage_blobs


  validates_presence_of :oid, :size
  validates_uniqueness_of :oid, case_sensitive: false

  # rubocop:todo Rails/InverseOf
  has_many :storage_replicas, class_name: "Storage::Replica", foreign_key: :storage_blob_id
  has_many :storage_references, class_name: "Storage::Reference", foreign_key: :storage_blob_id
  # rubocop:enable Rails/InverseOf

  def storage_partition
    oid[0]
  end

  def fileservers(host: nil, datacenter: nil)
    GitHub::Storage::Allocator.hosts_for_blob(id, host: host, datacenter: datacenter).map { |h| GitHub.storage_replicate_fmt % h }
  end

  def self.create_for_uploadable(meta)
    GitHub::Storage::Creator.create_blob(meta)
    where(oid: meta[:oid]).first
  end
end
