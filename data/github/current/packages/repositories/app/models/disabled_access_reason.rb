# typed: strict
# frozen_string_literal: true

class DisabledAccessReason < ApplicationRecord::Domain::DisabledAccessReasons
  validates_presence_of  :flagged_item_id
  validates_presence_of  :flagged_item_type
end
