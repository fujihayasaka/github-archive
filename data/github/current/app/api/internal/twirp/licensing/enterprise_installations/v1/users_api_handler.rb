# typed: true
# frozen_string_literal: true

require "monolith-twirp-licensing-enterprise_installations"

module Api::Internal::Twirp::Licensing
  module EnterpriseInstallations
    module V1
      # Handler for the MonolithTwirp::Licensing::EnterpriseInstallations::V1::UsersAPIService
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["licensing"]
        handles_service MonolithTwirp::Licensing::EnterpriseInstallations::V1::UsersAPIService

        DEFAULT_PAGE_SIZE = 5000
        GHAS_SKU = "ghas_licenses"
        GHEC_SKU = "ghec_licenses"

        # Public: Implementation of the GetUsers Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Licensing::EnterpriseInstallations::V1::GetUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Licensing::EnterpriseInstallations::V1::GetUsersResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Licensing::EnterpriseInstallations::V1::GetUsersRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(T.any(MonolithTwirp::Licensing::EnterpriseInstallations::V1::GetUsersResponse, Twirp::Error))
        end
        def get_users(req, env)
          unless enterprise_installation_id = id_argument(req.enterprise_installation_id)
            return Twirp::Error.invalid_argument("enterprise_installation_id is required", argument: "enterprise_installation_id")
          end

          # Customer requested
          page_size = req.page_size > 0 ? req.page_size : DEFAULT_PAGE_SIZE
          handle_request(enterprise_installation_id, req.page_token, page_size)
        end

        private

        sig { params(enterprise_installation_id: Integer, page_token: String, page_size: Integer).returns(T.any(MonolithTwirp::Licensing::EnterpriseInstallations::V1::GetUsersResponse, Twirp::Error)) }
        def handle_request(enterprise_installation_id, page_token, page_size)
          users = T.let([], T::Array[MonolithTwirp::Licensing::EnterpriseInstallations::V1::User])
          cursor = page_token.to_i
          next_page_token = ""

          unless enterprise_installation = EnterpriseInstallation.find_by(id: enterprise_installation_id)
            return Twirp::Error.not_found("enterprise installation not found")
          end

          all_enterprise_installation_ids = enterprise_installation
            .user_accounts
            .where("enterprise_installation_user_accounts.id > ?", cursor)
            .order(id: :asc)
            .pluck(:id)

          is_last_page = all_enterprise_installation_ids.size <= page_size
          page_ids = all_enterprise_installation_ids.first(page_size)

          if page_ids.any?
            enterprise_installation.user_accounts.includes(:emails, :business_user_account).where(id: page_ids).each do |user_account|
              skus = [GHEC_SKU]
              skus << GHAS_SKU if user_account.using_advanced_security

              users << MonolithTwirp::Licensing::EnterpriseInstallations::V1::User.new(
                id: user_account&.business_user_account&.user_id,
                enterprise_installation_user_account_id: user_account.id,
                primary_email: user_account.emails.find(&:primary)&.email,
                product_skus: skus,
              )
            end

            next_page_token = page_ids.last.to_s unless is_last_page
          end

          MonolithTwirp::Licensing::EnterpriseInstallations::V1::GetUsersResponse.new(
            users: users,
            next_page_token: next_page_token,
          )
        end
      end
    end
  end
end
