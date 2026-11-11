# typed: strict
# frozen_string_literal: true

module Repositories
  RefUpdateAttributes = Data.define(:id, :push_id, :repository_id, :before_oid, :after_oid, :ref, :ref_update_type)
end
