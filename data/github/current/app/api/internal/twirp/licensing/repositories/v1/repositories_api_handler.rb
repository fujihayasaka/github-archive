# typed: true
# frozen_string_literal: true

require "monolith-twirp-licensing-repositories"

module Api::Internal::Twirp::Licensing
  module Repositories
    module V1
      # Handler for the MonolithTwirp::Licensing::Repositories::V1::RepositoriesAPIService
      class RepositoriesAPIHandler < Api::Internal::Twirp::Handler
        include Scientist
        include Api::Internal::Twirp::Licensing::CodeQualityLicensifyEnablement

        allow_access_for :client, allowed_clients: ["licensing"]
        handles_service MonolithTwirp::Licensing::Repositories::V1::RepositoriesAPIService

        # Public: Implementation of the GetRepositoryInformation Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Licensing::Repositories::V1::GetRepositoryInformationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Licensing::Repositories::V1::GetRepositoryInformationResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Licensing::Repositories::V1::GetRepositoryInformationRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(T.any(MonolithTwirp::Licensing::Repositories::V1::GetRepositoryInformationResponse, Twirp::Error))
        end
        def get_repository_information(req, env)
          unless repo_id = id_argument(req.id)
            return Twirp::Error.invalid_argument("id is required", argument: "id")
          end

          repo = T.cast(::Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
          unless repo
            return Twirp::Error.not_found("repository not found")
          end

          ::Failbot.push "gh.repository.id": repo.id

          deleted_owner_customer_id = deleted_owner_customer_id_for(repo)
          enabled_products = get_enabled_products(repo)
          enterprise_managed_owner = get_enterprise_managed_owner(repo)

          repository = MonolithTwirp::Licensing::Repositories::V1::Repository.new(
            id: repo.id,
            visibility: handle_visibility(repo.visibility),
            parent_id: repo.parent_id,
            is_fork: repo.fork?,
            is_advisory_workspace: repo.advisory_workspace?,
            is_active: repo.active?,
            is_archived: repo.archived?,
            owner_customer_id: Licensing::Customer.id_for(repo),
            deleted_owner_customer_id: deleted_owner_customer_id,
            enabled_products: enabled_products,
            enterprise_managed_owner: enterprise_managed_owner,
          )

          MonolithTwirp::Licensing::Repositories::V1::GetRepositoryInformationResponse.new(
            repository: repository,
            collaborator_ids: req.include_collaborators ? get_collaborator_ids(repo) : [],
          )
        end

        private

        def handle_visibility(visibility)
          case visibility.to_sym
          when :public
            MonolithTwirp::Licensing::Repositories::V1::Repository::Visibility::VISIBILITY_PUBLIC
          when :private
            MonolithTwirp::Licensing::Repositories::V1::Repository::Visibility::VISIBILITY_PRIVATE
          when :internal
            MonolithTwirp::Licensing::Repositories::V1::Repository::Visibility::VISIBILITY_INTERNAL
          else
            MonolithTwirp::Licensing::Repositories::V1::Repository::Visibility::VISIBILITY_INVALID
          end
        end

        sig { params(repo: Repository).returns(T::Array[Integer]) }
        def get_collaborator_ids(repo)
          return [] if repo.advisory_workspace? || repo.fork? || repo.public? || !repo.active?

          ::Ability.from("abilities FORCE INDEX(subject_and_actor_and_priority_and_action)")
            .where(
                subject_id: repo.id,
                subject_type: "Repository",
                actor_type: "User",
                priority: Ability.priorities[:direct],
              ).distinct
            .pluck(:actor_id)
        end

        sig { params(repo: Repository).returns(T.nilable(Integer)) }
        def deleted_owner_customer_id_for(repo)
          return nil unless repo.owner&.is_a?(Organization)

          org = T.cast(repo.owner, Organization)
          return nil unless org.soft_deleted?

          org.business_id.to_i > 0 ? Business.find_by(id: org.business_id)&.customer_id : nil
        end

        sig { params(repo: Repository).returns(T::Array[Integer]) }
        def get_enabled_products(repo)
          enabled_products = []

          # Follow the logic from app/api/internal/twirp/code_scanning/turboghas/v1/turboghas_api_handler.rb#L214-L228
          owner = repo.owner
          return enabled_products unless owner

          billable_entity = AdvancedSecurityLicense.billable_entity(owner)
          return enabled_products unless billable_entity

          # bundled customers are considered as having all features ON
          if billable_entity.advanced_security_products_bundled?
            if repo.advanced_security_enabled?
              enabled_products << MonolithTwirp::Licensing::Repositories::V1::Product::PRODUCT_GHAS
            end
          else
            # This is the same check as in packages/secret_scanning/app/public/secret_scanning/instrumentation/feature_toggled_publisher.rb
            # To publish the message used by Licensify to know the feature has been enabled.
            if repo.security_feature_configured?(:SECRET_SCANNING)
              enabled_products << MonolithTwirp::Licensing::Repositories::V1::Product::PRODUCT_SECRET_PROTECTION
            end

            # This is how the turobghas api determineds code security is enabled
            # app/api/internal/twirp/code_scanning/turboghas/v1/turboghas_api_handler.rb
            if SecurityProduct::CodeSecurity.new(repo).enabled?
              enabled_products << MonolithTwirp::Licensing::Repositories::V1::Product::PRODUCT_CODE_SECURITY
            end
          end

          # Code Quality is independent of the bundled/unbundled GHAS logic
          if code_quality_enabled_for_licensify?(repo)
            enabled_products << MonolithTwirp::Licensing::Repositories::V1::Product::PRODUCT_CODE_QUALITY
          end

          enabled_products.uniq
        end

        sig { params(repo: Repository).returns(T.nilable(MonolithTwirp::Licensing::Repositories::V1::EnterpriseManagedOwner)) }
        def get_enterprise_managed_owner(repo)
          owner = repo.owner
          return nil unless owner.is_a?(User) && owner.is_enterprise_managed? && owner.enterprise_managed_business.present?

          MonolithTwirp::Licensing::Repositories::V1::EnterpriseManagedOwner.new(
            is_enterprise_managed_user: true,
            enterprise_managed_customer_id: owner.enterprise_managed_business.customer_id,
          )
        end
      end
    end
  end
end
