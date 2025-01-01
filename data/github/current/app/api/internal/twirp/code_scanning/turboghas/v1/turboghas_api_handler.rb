# typed: strict
# frozen_string_literal: true

require "monolith-twirp-code_scanning-turboghas"

module Api::Internal::Twirp::CodeScanning
  module Turboghas
    module V1
      # Handler for the MonolithTwirp::CodeScanning::Turboghas::V1::TurboghasAPIService
      class TurboghasAPIHandler < Api::Internal::Twirp::Handler

        # these endpoints are used by a global indexing process
        exempt_from_tenant_context_requirement only: [
          :get_entities,
          :get_users,
          :get_repositories,
        ]

        resolve_tenant_context only: [:get_billable_users, :find_users_by_emails] do |req, _env|
          begin
            case req
            when MonolithTwirp::CodeScanning::Turboghas::V1::FindUsersByEmailsRequest
              next ::Business.find(req.business_id) if req.business_id.nonzero?
              next ::Repositories::Public.get_active_or_deleted!(req.repository_id).owner&.business
            when MonolithTwirp::CodeScanning::Turboghas::V1::GetBillableUsersRequest
              next ::User.find(req.owner_id).business
            end
          rescue ActiveRecord::RecordNotFound => err
            Twirp::Error.not_found(err.message)
          end
        end

        allow_access_for :client, allowed_clients: ["turboghas"]
        handles_service MonolithTwirp::CodeScanning::Turboghas::V1::TurboghasAPIService

        # Public: Implementation of the FindUsersByEmails Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::CodeScanning::Turboghas::V1::FindUsersByEmailsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::CodeScanning::Turboghas::V1::FindUsersByEmailsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::CodeScanning::Turboghas::V1::FindUsersByEmailsRequest,
            env: T::Hash[String, T.untyped],
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def find_users_by_emails(req, env)
          business_id = id_argument(req.business_id)
          repository_id = id_argument(req.repository_id)

          repository = Repository.preload(:owner).where(id: repository_id, active: true).first
          return Twirp::Error.not_found("repository not found", argument: "repository_id") unless repository.present?

          # give customers a pass if the repository is being imported
          # is_importing? is only true while the import is actually happening and if hydro is lagging we may miss this key
          # being set as it is deleted afterwards
          # in future we would want to use repository.import.completed, however it is currently not being updated
          recently_imported = repository.import.present? && (req.pushed_at&.to_time || Time.now).before?(T.must(repository.import).updated_at + 1.hour)

          if repository.is_importing? || recently_imported
            GitHub.dogstats.count("turboghas_api_handler.import.skipped_emails", req.emails.size)
            return {}
          end

          business = Business.where(id: business_id).first if business_id.present?
          business ||= repository.owner&.business
          business ||= Business.enterprise_managed_business_for(resource: repository)
          business ||= GitHub.global_business if GitHub.single_business_environment?

          emails = req.emails.reject { |email| UserEmail.belongs_to_a_bot?(email) }

          return {} if emails.empty?

          users = User.find_by_emails(emails, business: business).filter_map do |email, user|
            { email: email.b, id: user.id, login: user.login, created_at: Google::Protobuf::Timestamp.new(seconds: user.created_at.to_i) } unless user.bot?
          end

          { users: users }
        end

        # Public: Implementation of the GetBillableUsers Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::CodeScanning::Turboghas::V1::GetBillableUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::CodeScanning::Turboghas::V1::GetBillableUsersResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::CodeScanning::Turboghas::V1::GetBillableUsersRequest,
            env: T::Hash[String, T.untyped],
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def get_billable_users(req, env)
          owner_id = id_argument(req.owner_id)
          return Twirp::Error.invalid_argument("must be provided", argument: "owner_id") unless owner_id

          ::Failbot.push(owner_id: owner_id)

          owner = User.where(id: owner_id).first
          return Twirp::Error.not_found("not found", argument: "owner_id") unless owner.present?

          billable_entity = AdvancedSecurityLicense.billable_entity(owner)

          return Twirp::Error.not_found("billable entity does not exist", argument: "owner_id") unless billable_entity.present?

          ::Failbot.push(entity_id: billable_entity.id)

          entity_type = case
          when billable_entity.is_a?(User)
            :ENTITY_TYPE_USER
          when billable_entity.is_a?(Business)
            :ENTITY_TYPE_BUSINESS
          end

          return Twirp::Error.failed_precondition("ghas tracking is disabled for this entity") if billable_entity.feature_enabled?(:turboghas_entity_too_large)

          {
            billable_entity_type: entity_type,
            billable_entity_id: billable_entity.id,
            user_ids: billable_entity.advanced_security_license.user_ids,
          }
        end

        # Public: Implementation of the GetEntities Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::CodeScanning::Turboghas::V1::GetEntitiesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::CodeScanning::Turboghas::V1::GetEntitiesResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::CodeScanning::Turboghas::V1::GetEntitiesRequest,
            env: T::Hash[String, T.untyped],
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def get_entities(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "entities") if req.entities.blank?

          entities = req.entities.group_by(&:type).flat_map do |type, entities|
            entity_type = case type
            when :ENTITY_TYPE_BUSINESS then Business
            when :ENTITY_TYPE_USER then User.preload(business_membership: [:business])
            else return Twirp::Error.internal("invalid entity type")
            end

            entity_type.where(id: entities.map(&:id)).filter_map do |entity|
              next unless entity.present?
              next if entity.feature_enabled?(:turboghas_entity_too_large)

              user_ids = entity.advanced_security_license.user_ids

              { id: entity.id, type: type, user_ids: user_ids }
            end
          end

          { entities: entities }
        end

        # Public: Implementation of the GetRepositories Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::CodeScanning::Turboghas::V1::GetRepositoriesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::CodeScanning::Turboghas::V1::GetRepositoriesResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::CodeScanning::Turboghas::V1::GetRepositoriesRequest,
            env: T::Hash[String, T.untyped],
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def get_repositories(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "repository_ids") if req.repository_ids.blank?

          repositories = Repository.active.where(id: req.repository_ids.to_a).preload(:owner)

          preloader = ActiveRecord::Associations::Preloader.new(records: repositories.select { |repo| repo.owner&.organization? }, associations: { owner: { business_membership: [:business] } })
          preloader.call

          # preload configuration entries for secret scanning check
          Configurable.preload_configuration(repositories + repositories.flat_map(&:configuration_owners).uniq)

          repositories = repositories.filter_map do |repository|
            owner = repository.owner
            next unless owner.present?

            billable_entity = AdvancedSecurityLicense.billable_entity(owner)
            next unless billable_entity.present?

            entity_type = case
            when billable_entity.is_a?(User)
              :ENTITY_TYPE_USER
            when billable_entity.is_a?(Business)
              :ENTITY_TYPE_BUSINESS
            end

            owner_type = case
            when owner.user? then :USER_TYPE_USER
            when owner.is_a?(Organization) && owner.organization? then :USER_TYPE_ORGANIZATION
            else
              return Twirp::Error.internal("invalid owner type")
            end

            bundled_customer = billable_entity.advanced_security_products_bundled?

            advanced_security_enabled = MonolithTwirp::CodeScanning::Turboghas::V1::Feature::FEATURE_NONE

            # bundled customers are considered has having all features ON
            if bundled_customer && repository.advanced_security_enabled?
              advanced_security_enabled |= MonolithTwirp::CodeScanning::Turboghas::V1::Feature::FEATURE_ALL
            end
            if SecretScanning::Features::Repo::TokenScanning.new(repository).enabled?
              advanced_security_enabled |= MonolithTwirp::CodeScanning::Turboghas::V1::Feature::FEATURE_SECRET_SCANNING
            end
            if repository.dependency_review_enabled?
              advanced_security_enabled |= MonolithTwirp::CodeScanning::Turboghas::V1::Feature::FEATURE_DEPENDABOT
            end
            if bundled_customer
              # for bundled repositories keep using our heuristic so that we can continue to emit speculative market data
              if repository.code_scanning_active?
                advanced_security_enabled |= MonolithTwirp::CodeScanning::Turboghas::V1::Feature::FEATURE_CODE_SCANNING
              end
            else
              if SecurityProduct::CodeSecurity.new(repository).enabled?
                advanced_security_enabled |= MonolithTwirp::CodeScanning::Turboghas::V1::Feature::FEATURE_CODE_SCANNING
                # paid dependabot features are currently enabled and disabled by code security
                # having one means you must also have the other
                advanced_security_enabled |= MonolithTwirp::CodeScanning::Turboghas::V1::Feature::FEATURE_DEPENDABOT
              end
            end

            [repository.id, {
              entity: {
                type: entity_type,
                id: billable_entity.id,
              },
              advanced_security_enabled:,
              owner_id: owner.id,
              name: repository.name,
              is_archived: repository.archived?,
              is_public: repository.public?,
              owner: {
                type: owner_type,
                login: owner.login,
                is_enterprise_managed: owner.is_enterprise_managed?,
                created_at: Google::Protobuf::Timestamp.new(seconds: owner.created_at.to_i),
              },
            }]
          end.to_h
          {
            repositories: repositories,
          }
        end

        # Public: Implementation of the GetUsers Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::CodeScanning::Turboghas::V1::GetUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::CodeScanning::Turboghas::V1::GetUsersResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::CodeScanning::Turboghas::V1::GetUsersRequest,
            env: T::Hash[String, T.untyped],
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def get_users(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "user_ids") if req.user_ids.blank?

          users = User.where(id: req.user_ids.to_a).filter_map do |user|
            user_type = case
            when user.user? then :USER_TYPE_USER
            when user.is_a?(Organization) && user.organization? then :USER_TYPE_ORGANIZATION
            else
              next
            end

            [user.id, {
              login: user.login,
              type: user_type,
              is_enterprise_managed: user.is_enterprise_managed?,
              created_at: Google::Protobuf::Timestamp.new(seconds: user.created_at.to_i),
            }]
          end.to_h
          {
            users: users,
          }
        end
      end
    end
  end
end
