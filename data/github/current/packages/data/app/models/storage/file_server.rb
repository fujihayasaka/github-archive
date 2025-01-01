# typed: true
# frozen_string_literal: true

class Storage::FileServer < ApplicationRecord::Domain::Storage
  self.table_name = :storage_file_servers

  validates_presence_of :host

  # rubocop:todo Rails/InverseOf
  has_many :partitions, class_name: "Storage::Partition", foreign_key: :storage_file_server_id
  # rubocop:enable Rails/InverseOf
end
