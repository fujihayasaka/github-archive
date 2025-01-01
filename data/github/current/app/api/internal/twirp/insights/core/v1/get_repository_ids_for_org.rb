# typed: true
# frozen_string_literal: true

require "google/protobuf/well_known_types"

module Api::Internal::Twirp::Insights
  module Core
    module V1
      class GetRepositoryIdsForOrg

        DEFAULT_WATERMARK = Google::Protobuf::Timestamp.new(seconds: 0)
        DEFAULT_BATCH_SIZE = 1_000

        def self.call(req, env)
          ActiveRecord::Base.connected_to(role: :reading) do
            new(req, env).call
          end
        end

        def initialize(req, env)
          @req = req
          @env = env
          @org_id = req.org_id
          @cursor = req.cursor
          @watermark = req.watermark.nil? ? DEFAULT_WATERMARK : req.watermark
          @batch_size = req.batch_size.zero? ? DEFAULT_BATCH_SIZE : req.batch_size
        end

        def call
          if @org_id.zero?
            return Twirp::Error.invalid_argument("must be non-zero", argument: "org_id")
          end

          ids = Repository.where(owner_id: @org_id).where("updated_at >= ?", @watermark.to_time)
            .where("id >= ?", @cursor).order(:id).limit(@batch_size).pluck(:id)

          { repo_ids: ids, next_cursor: next_cursor(ids) }
        end

        def next_cursor(data)
          return 0 unless data
          if data.size < @batch_size
            0
          else
            last_id = data.last
            (last_id + 1)
          end
        end
      end
    end
  end
end
