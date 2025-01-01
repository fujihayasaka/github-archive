# typed: true
# frozen_string_literal: true

class Storage::Replica < ApplicationRecord::Domain::Storage
  self.table_name = :storage_replicas


  validates_presence_of :host, :storage_blob_id
  validates_uniqueness_of :host, scope: :storage_blob_id, case_sensitive: false

  belongs_to :storage_blob, class_name: "Storage::Blob"

  def self.create_for_uploadable(uploadable, hosts:)
    GitHub::Storage::Creator.track_uploadable_storage(uploadable,
      hosts: hosts,
    )
  end

  # Public: Determines the file servers that the given Storage::Blob should be
  # replicated to. This is not listing the file servers that the blob is
  # currently on.
  def self.replication_fileservers
    GitHub::Storage::Allocator.least_loaded_fileservers
  end
end
