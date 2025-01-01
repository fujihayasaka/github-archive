# typed: true
# frozen_string_literal: true

class ImportItemError < ApplicationRecord::Domain::Repositories
  belongs_to :import_item

  validates_presence_of :import_item_id
end
