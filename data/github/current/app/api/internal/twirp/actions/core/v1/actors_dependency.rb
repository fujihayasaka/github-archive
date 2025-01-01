# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      module ActorsDependency
        def build_actor(actor)
          if actor.is_a?(User) && actor.user?
            build_user(actor)
          elsif actor.is_a?(Bot)
            build_user(actor)
          elsif actor.is_a?(Organization) && actor.organization?
            build_org(actor)
          elsif actor.is_a?(Repository)
            build_repo(actor)
          elsif actor.is_a?(Business)
            build_business(actor)
          else
            { id: actor.id, type: :TYPE_INVALID }
          end
        end

        def proto_timestamp(timestamp)
          Google::Protobuf::Timestamp.new(seconds: timestamp.to_i)
        end

        def build_user(user)
          {
            id: user.id,
            id_string: user.login_for_api(use: @env[:serialize_login_selection]),
            type: :TYPE_USER,
            plan_name: get_actions_plan(user),
            is_private: nil,
            created_at: proto_timestamp(user.created_at),
            global_id: { global_id: get_global_id(user) },
            is_hammy: { value: user.hammy? }
          }
        end

        def build_org(org)
          {
            id: org.id,
            id_string: org.login_for_api(use: @env[:serialize_login_selection]),
            type: :TYPE_ORGANIZATION,
            plan_name: get_actions_plan(org),
            is_private: nil,
            created_at: proto_timestamp(org.created_at),
            global_id: { global_id: get_global_id(org) },
            is_hammy: { value: org.hammy? }
          }
        end

        def build_repo(repo)
          {
            id: repo.id,
            id_string: repo.name_with_owner_for_api(use: @env[:serialize_login_selection]),
            type: :TYPE_REPOSITORY,
            plan_name: get_actions_plan(repo.owner),
            is_private: { value: repo.private? },
            created_at: proto_timestamp(repo.created_at),
            global_id: { global_id: get_global_id(repo) },
            is_hammy: nil
          }
        end

        def build_business(business)
          {
            id: business.id,
            id_string: business.slug,
            type: :TYPE_BUSINESS,
            plan_name: get_actions_plan(business),
            is_private: nil,
            created_at: proto_timestamp(business.created_at),
            global_id: { global_id: get_global_id(business) },
            is_hammy: nil
          }
        end

        def get_actions_plan(actor)
          ActionsPlanOwner.new(actor).plan_name
        end

        def get_global_id(actor)
          use_next_gid = !GitHub.enterprise?
          use_next_gid ? actor.next_global_id : actor.global_relay_id
        end

      end
    end
  end
end
