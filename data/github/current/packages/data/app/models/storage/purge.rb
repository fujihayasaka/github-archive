# typed: true
# frozen_string_literal: true

class Storage::Purge < ApplicationRecord::Domain::Storage
  self.table_name = :storage_purges


  belongs_to :storage_blob, class_name: "Storage::Blob"

  validates_presence_of :storage_blob

  # We should not try to purge the same blob twice.
  validates_uniqueness_of :storage_blob_id
end
