# typed: strict
# frozen_string_literal: true

module Repositories
  PushAttributes = Data.define(:id, :repository_id, :pusher_id, :before, :after, :ref, :created_at, :updated_at, :pushed_at, :push_type)
end
