# typed: strict
# frozen_string_literal: true

module Stores
  StoreAttributes = Data.define(:id, :spokes_id, :created_at, :deleted_at, :owner_id, :state)
end
