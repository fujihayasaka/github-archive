# typed: false
# frozen_string_literal: true
module Api::Internal::Twirp::Insights
  module Core
    module V1
      class GetOrgInternalRepositories
        DEFAULT_BATCH_SIZE = 10_000
        QUERY_BATCH_SIZE = 2_000

        attr_reader :req, :env, :org_id, :cursor, :batch_size

        def self.call(req, env)
          ActiveRecord::Base.connected_to(role: :reading) do
            new(req, env).call
          end
        end

        def initialize(request, env)
          @req = request
          @env = env
          @org_id = req.org_id
          @cursor = req.cursor
          @batch_size = req.batch_size.zero? ? DEFAULT_BATCH_SIZE : req.batch_size
        end

        def call
          if org_id.zero?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "org_id")
          end

          org = Organization.find_by(id: org_id)
          if org.nil?
            return Twirp::Error.not_found("organization does not exist", argument: "org_id")
          end

          unless org.supports_internal_repositories?
            return Twirp::Error.invalid_argument("Organization does not support internal repositories", argument: "org_id")
          end

          data = []
          InternalRepository.where("internal_repositories.id >= ?", cursor).joins(:repository).where("repositories.owner_id": org.id, business_id: org.business.id).order(:id).limit(batch_size).find_each(batch_size: QUERY_BATCH_SIZE) do |internal_repo|
            data << serialize_repo(internal_repo)
          end

          { data: data, next_cursor: next_cursor(org, data&.last) }
        end

        private

        def serialize_repo(internal_repo)
          {
            id: internal_repo.id_before_type_cast,
            repository_id: internal_repo.repository_id_before_type_cast,
            business_id: internal_repo.business_id_before_type_cast,
            created_at: internal_repo.created_at_before_type_cast,
            updated_at: internal_repo.updated_at_before_type_cast
          }
        end

        def next_cursor(org, last_repo)
          return -1 unless last_repo
          last_id = last_repo[:id]
          next_records_exists = InternalRepository.where("id > ?", last_id).exists?(business_id: org.business.id)
          next_records_exists ? (last_id + 1) : -1
        end
      end
    end
  end
end
