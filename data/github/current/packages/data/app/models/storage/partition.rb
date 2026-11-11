# typed: true
# frozen_string_literal: true

class Storage::Partition < ApplicationRecord::Domain::Storage
  self.table_name = :storage_partitions


  validates_presence_of :storage_file_server_id, :partition, :disk_free, :disk_used

  # rubocop:todo Rails/InverseOf
  belongs_to :storage_file_server, class_name: "Storage::FileServer", foreign_key: "storage_file_server_id"
  # rubocop:enable Rails/InverseOf

  def self.total_for(fileservers)
    where(storage_file_server_id: fileservers.map(&:id), partition: "0").index_by(&:storage_file_server_id)
  end
end
