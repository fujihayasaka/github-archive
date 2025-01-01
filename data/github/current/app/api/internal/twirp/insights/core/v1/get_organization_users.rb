# typed: true
# frozen_string_literal: true
module Api::Internal::Twirp::Insights
  module Core
    module V1
      class GetOrganizationUsers
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
          members_ids = Ability.select(:actor_id)
            .where(subject_id: org.id, subject_type: org.type, actor_type: "User", priority: Ability.priorities[:direct])
            .where("actor_id >= ?", cursor)
            .order(:actor_id)
            .limit(batch_size)

          User.where(id: members_ids.pluck(:actor_id)).find_each(batch_size: QUERY_BATCH_SIZE) do |user|
            data << serialize_member(user)
          end

          { data: data, next_cursor: next_cursor(org, members_ids.last&.actor_id) }
        end

        private

        def serialize_member(member)
          {
            id: member.id_before_type_cast,
            login: member.login_before_type_cast,
            disabled:  member.disabled_before_type_cast,
            spammy: member.spammy_before_type_cast,
            type: member.type_before_type_cast,
            suspended_at: member.suspended_at_before_type_cast,
            organization_billing_email: member.organization_billing_email_before_type_cast,
            time_zone_name: member.time_zone_name_before_type_cast,
            spammy_reason: member.spammy_reason_before_type_cast,
            primary_language_name_id: member.primary_language_name_id_before_type_cast,
            created_at: member.created_at_before_type_cast,
            updated_at: member.updated_at_before_type_cast
          }
        end

        def next_cursor(org, last_member_id)
          return -1 unless last_member_id

          next_records_exists = Ability
                                  .where("actor_id > ?", last_member_id)
                                  .exists?(subject_id: org.id, subject_type: org.type, actor_type: "User", priority: Ability.priorities[:direct])

          next_records_exists ? (last_member_id + 1) : -1
        end
      end
    end
  end
end
