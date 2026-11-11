# typed: true
# frozen_string_literal: true

class Storage::Reference < ApplicationRecord::Domain::Storage
  self.table_name = :storage_references

  enum :state, {
    new: 0,
    uploaded: 1,
    deleted: 2,
  }, prefix: true

  validates_presence_of :storage_blob_id, :uploadable_id, :uploadable_type
  validates_uniqueness_of :uploadable_id, scope: [:uploadable_type, :storage_blob_id]

  belongs_to :storage_blob, class_name: "Storage::Blob"
  belongs_to :uploadable, polymorphic: true
end
