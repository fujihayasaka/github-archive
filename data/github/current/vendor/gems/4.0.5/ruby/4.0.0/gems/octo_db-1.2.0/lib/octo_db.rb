# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module OctoDb
  autoload :ApplicationRecord, "octo_db/application_record"
  autoload :ArelLiterals, "octo_db/arel_literals"
  autoload :QueryBatching, "octo_db/query_batching"
  autoload :LikeQuery, "octo_db/like_query"
end
