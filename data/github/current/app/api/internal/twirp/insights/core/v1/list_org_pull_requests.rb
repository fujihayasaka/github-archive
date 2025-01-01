# typed: true
# frozen_string_literal: true
module Api::Internal::Twirp::Insights
  module Core
    module V1
      class ListOrgPullRequests
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

          data = []
          repository_ids = org.repositories.pluck(:id)
          PullRequest.where("pull_requests.id >= ?", cursor).where(repository_id: repository_ids).order(:id).limit(batch_size).find_each(batch_size: QUERY_BATCH_SIZE) do |pull_request|
            data << serialize_pr(pull_request)
          end

          { data: data, next_cursor: next_cursor(data) }
        end

        private

        def serialize_pr(pull_request)
          {
            id: pull_request.id_before_type_cast,
            base_sha: pull_request.base_sha_before_type_cast,
            head_sha: pull_request.head_sha_before_type_cast,
            repository_id: pull_request.repository_id_before_type_cast,
            user_id: pull_request.user_id_before_type_cast,
            created_at: pull_request.created_at_before_type_cast,
            updated_at: pull_request.updated_at_before_type_cast,
            base_repository_id: pull_request.base_repository_id_before_type_cast,
            head_repository_id: pull_request.head_repository_id_before_type_cast,
            merged_at: pull_request.merged_at_before_type_cast,
            base_user_id: pull_request.base_user_id_before_type_cast,
            head_user_id: pull_request.head_user_id_before_type_cast,
            is_mergeable: if pull_request.mergeable_before_type_cast.nil?
                            false
                          else
                            pull_request.mergeable_before_type_cast.zero? ? false : true
                          end,
            merge_commit_sha: pull_request.merge_commit_sha_before_type_cast,
            fork_collab_state: pull_request.fork_collab_state_before_type_cast,
            contributed_at_timestamp: pull_request.contributed_at_timestamp_before_type_cast,
            contributed_at_offset: pull_request.contributed_at_offset_before_type_cast,
            is_user_hidden: if pull_request.user_hidden_before_type_cast.nil?
                              false
                            else
                              pull_request.user_hidden_before_type_cast.zero? ? false : true
                            end,
            base_sha_on_merge: pull_request.base_sha_on_merge_before_type_cast,
            is_work_in_progress: if pull_request.work_in_progress_before_type_cast.nil?
                                   false
                                 else
                                   pull_request.work_in_progress_before_type_cast.zero? ? false : true
                                 end,
            reviewable_state: pull_request.reviewable_state_before_type_cast,
            reviews_with_body_count: pull_request.reviews_with_body_count_before_type_cast,
            review_comments_with_body_count: pull_request.review_comments_with_body_count_before_type_cast
          }
        end

        def next_cursor(data)
          return -1 unless data
          if data.size < batch_size
            -1
          else
            last_id = data.last[:id]
            (last_id + 1)
          end
        end

      end
    end
  end
end
