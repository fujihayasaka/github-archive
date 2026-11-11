# typed: true
# frozen_string_literal: true

require "monolith-twirp-support-helphub"

module Api::Internal::Twirp::Support
  module HelpHub
    module V1
      # Provides access to Support-relevant data.
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        include Api::Internal::Twirp::Support::HelpHub::V1::UsedProductsDependency

        handles_service(MonolithTwirp::Support::HelpHub::V1::UsersAPIService)

        allow_access_for :user, :client, allowed_clients: %w(helphub).freeze

        FIND_USERS_HARD_LIMIT = 100
        GET_BILLING_INFO_HARD_LIMIT = 100
        GET_ORGANIZATIONS_RESPONSE_LIMIT = 200
        GET_SPAMMY_ORGANIZATIONS_LIMIT = 5

        # Public: Implementation of the FindUsers Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::FindUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of users, suitable for use in
        # a MonolithTwirp::Support::HelpHub::V1::FindUsersResponse.
        def find_users(req, env)
          scope_or_error = get_users_by_id(req.ids, argument_name: "ids",
            limit: FIND_USERS_HARD_LIMIT)
          if scope_or_error.is_a?(Twirp::Error)
            scope_or_error
          else
            {
              users: build_user_list(scope_or_error),
            }
          end
        end

        # Public: Implementation of the FindUserTwoFactorDetails Twirp RPC.
        def find_user_two_factor_details(req, env)
          user_id = id_argument(req.user_id, env[:user_id])
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end
          user = User.find_by(id: user_id)
          if user.nil?
            return Twirp::Error.not_found("user does not exist", argument: "user_id")
          end

          return { two_factor_detail: {} } unless user.user? && user.two_factor_authentication_enabled?

          two_factor_detail = {
            requirement_state:        user.account_two_factor_requirement_state,
            requirement_date:         user.two_factor_requirement_metadata&.required_by&.utc&.strftime("%Y-%m-%d"),
            has_authenticator_active: user.two_factor_configured_with?(:app),
            has_sms_active:           user.two_factor_configured_with?(:sms),
            has_sms_fallback:         user.two_factor_backup_sms_number.present?,
            has_recovery_code_viewed: T.must(user.two_factor_credential).recovery_codes_viewed?,
            has_recovery_gpg_keys:    !!user.gpg_keys.primary_keys.size.nonzero?,
            has_recovery_ssh_keys:    !!user.public_keys.to_a.count { |k| k.can_verify_account_ownership? }.nonzero?,
            has_recovery_pats:        !!user.personal_tokens_for_account_recovery(Time.current, limit: 200).count.nonzero?,
            has_gh_mobile_auth:       user.gh_mobile_auth_available?,
            has_security_keys:        !!user.u2f_registrations.security_keys.size.nonzero?,
            has_trusted_devices:      !!user.u2f_registrations.passkeys.size.nonzero?,
            has_organizations_with_requirement: !!user.affiliated_organizations_with_two_factor_requirement.count.nonzero?,
          }

          { two_factor_detail: }
        end

        # Public: Implementation of the GetBillingInfo Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::GetBillingInfoRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of billing info result for the users
        # a MonolithTwirp::Support::HelpHub::V1::GetBillingInfoResponse.
        def get_billing_info(req, env)
          scope_or_error = get_users_by_id(req.user_ids, argument_name: "user_ids",
            limit: GET_BILLING_INFO_HARD_LIMIT)
          if scope_or_error.is_a?(Twirp::Error)
            scope_or_error
          else
            {
              results: build_billing_info_list(scope_or_error),
            }
          end
        end

        # Public: Implementation of the GetRefundEligibility Twirp RPC.
        # Accepts a GetRefundEligibilityRequest and returns an array of GetRefundEligibilityResponse
        def get_refund_eligibility(req, env)
          user_id = id_argument(req.user_id, env[:user_id])
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end
          user = User.find_by(id: user_id)
          if user.nil?
            return Twirp::Error.not_found("user does not exist", argument: "user_id")
          end

          if req.products.empty?
            return Twirp::Error.invalid_argument("no products specified", argument: "products")
          end

          results = req.products.map do |product|
            case product
            when "copilot_individual" # This includes Copilot Pro and Copilot Pro Plus
              user.help_hub_eligibility.helphub_copilot_refund_eligibility
            else
              return Twirp::Error.invalid_argument("invalid product in #{req.products}", argument: "products")
            end
          end

          { results: }
        end

        # Public: Implementation of the GetContactApiTokenUser Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::GetContactApiTokenUserRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, the user id and creating oauth app result for the remote auth token
        # as a MonolithTwirp::Support::HelpHub::V1::GetContactApiTokenUserResponse.
        def get_contact_api_token_user(req, env)
          verified_token = User.verify_signed_auth_token(token: req.remote_auth, scope: "MobileSupportToken") ||
            User.verify_signed_auth_token(token: req.remote_auth, scope: "MonolithSupportToken")

          if verified_token.valid?
            {
              user_id: verified_token.user.id,
              app_id: verified_token.data["app_id"]
            }
          else
            Twirp::Error.not_found("invalid", argument: "remote_auth")
          end
        end

        # Public: Implementation of the GetTradeScreeningStatus Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::GetTradeScreeningStatus.
        #
        # Returns the Twirp response data as a Hash suitable for use in a
        # MonolithTwirp::Support::HelpHub::V1::GetTradeScreeningStatus.
        #
        def get_trade_screening_status(req, env)
          user_id = id_argument(req.user_id)
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          user = User.find_by(id: user_id)
          if user.nil?
            return Twirp::Error.not_found("user does not exist", argument: "user_id")
          end

          {
            restricted: user.has_strict_commercial_interaction_restriction?,
            humanized_status: user.humanize_trade_screening_status
          }
        end

        # Public: Implementation of the GetOrganizations Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::GetOrganizationsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a Hash suitable for use in a
        # MonolithTwirp::Support::HelpHub::V1::GetOrganizationsResponse.
        #
        # Returns no more than 100 organizations
        def get_organizations(req, env)
          user_id = id_argument(req.user_id, env[:user_id])
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          user = User.find_by(id: user_id)
          if user.nil?
            return Twirp::Error.not_found("user does not exist", argument: "user_id")
          end

          all_organizations_ids = (user.organizations.pluck(:id) +
                                  user.billing_manager_organizations.pluck(:id)).uniq
          organizations = Organization.where(id: all_organizations_ids)
            .limit(GET_ORGANIZATIONS_RESPONSE_LIMIT)
            .order(created_at: :desc)

          {
            results: build_organizations_info_list(organizations, user)
          }
        end

        # Public: Implementation of the GetOwnedSpammyOrganizations Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::GetOwnedSpammyOrganizations.
        #
        # Returns the Twirp response data as a Hash suitable for use in a
        # MonolithTwirp::Support::HelpHub::V1::GetOwnedSpammyOrganizations.
        def get_owned_spammy_organizations(req, env)
          user_id = id_argument(req.user_id, env[:user_id])
          return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id") unless user_id

          user = User.find_by(id: user_id)
          return Twirp::Error.not_found("user does not exist", argument: "user_id") unless user

          spammy_orgs = user.owned_organizations.spammy.limit(GET_SPAMMY_ORGANIZATIONS_LIMIT).map do |org|
            { display_login: org.display_login, spammy_reason: org.spammy_reason }
          end

          { results: spammy_orgs }
        end

        # Public: Implementation of the FindUsersByLogin Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::FindUserByLoginRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a Hash suitable for use in a
        # MonolithTwirp::Support::HelpHub::V1::FindUserByLoginResponse.
        def find_user_by_login(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "login") if req.login.blank?

          user = User.find_by(login: req.login)
          return Twirp::Error.not_found("user does not exist", argument: "login") if user.nil?

          { user_id: user.id, user: build_user_result(user) }
        end

        # Public: Implementation of the FindUsersByEmail Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::FindUserByEmailRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a Hash suitable for use in a
        # MonolithTwirp::Support::HelpHub::V1::FindUserByEmailResponse.
        def find_user_by_email(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "email") if req.email.blank?

          user = User.find_by_email(req.email)
          return Twirp::Error.not_found("user does not exist", argument: "email") if user.nil?

          { user_id: user.id, login: user.login, user: build_user_result(user) }
        end

        # Public: Implementation of the FindUserAssetByUrl Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::FindUserAssetByUrlRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a Hash suitable for use in a
        # MonolithTwirp::Support::HelpHub::V1::FindUserAssetByUrlResponse.
        def find_user_asset_by_url(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "url") if req.url.blank?

          result = AssetScanner.check_url(req.url.strip)
          return Twirp::Error.not_found("asset url invalid", argument: "url") unless result.success?

          asset = UserAsset.where(guid: result.match.asset_guid).first
          return Twirp::Error.not_found("asset does not exist", argument: "url") if asset.nil?

          { user_id: T.must(asset.uploader).id, login: T.must(asset.uploader).login, asset_id: asset.id }
        end

        # Public: Implementation of the FindFileattachmentByUrl Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::FindFileAttachmentByUrlRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a Hash suitable for use in a
        # MonolithTwirp::Support::HelpHub::V1::FindFileAttachmentByUrlResponse.
        def find_file_attachment_by_url(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "url") if req.url.blank?

          route = Rails.application.routes.recognize_path(req.url)
          controller = route.dig(:controller)
          return Twirp::Error.invalid_argument("file url invalid", argument: "url") unless controller == "attachments/repository_files" || controller == "attachments/legacy_repository_files"

          id = route[:id].to_i

          user = nil
          return Twirp::Error.not_found("user does not exist", argument: "user_id") if req.user_id.present? && req.user_id.positive? && (user = User.find_by(id: req.user_id)).nil?

          return Twirp::Error.not_found("file does not exist", argument: "url") if id.nil? || (file = RepositoryFile.find_by(id: id)).nil? || (file.using_new_url? && controller == "attachments/legacy_repository_files")

          repo = file.repository
          uploader = file.uploader

          result = { file_id: file.id, repo_id: T.must(repo).id, user_id: T.must(uploader).id, login: T.must(uploader).login }
          result[:is_uploader_or_repo_admin] = user.id == T.must(uploader).id || T.must(repo).admin_ids.include?(user.id) unless user.nil?
          result
        end

        # Public: Refund and cancel a subscription item
        # subscription_item_id - the id of Billing::SubscriptionItem to refund and cancel
        # returns RefundSubscriptionItemResponse hash
        def refund_subscription_item(req, env)
          subscription_item_id = id_argument(req.subscription_item_id, env[:subscription_item_id])
          unless subscription_item_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "subscription_item_id")
          end
          subscription_item = Billing::SubscriptionItem.find_by(id: subscription_item_id)
          if subscription_item.nil?
            return Twirp::Error.not_found("subscription_item does not exist", argument: "subscription_item_id")
          end
          copilot_product = subscription_item.subscribable
          if copilot_product.nil?
            return Twirp::Error.not_found("subscribable product does not exist", argument: "subscription_item_id")
          end
          account = subscription_item.user
          if account.nil?
            return Twirp::Error.not_found("account not found", argument: "subscription_item_id")
          end
          full_refund = subscription_item.created_at.after?(31.days.ago)
          if full_refund.nil?
            return Twirp::Error.invalid_argument("created_at does not exist", argument: "subscription_item_id")
          end

          Audit.context.push(support_context: "helphub refund_copilot_individual")
          result = Billing::Public::SubscriptionItem.cancel_and_refund(product: copilot_product, account: account, full_refund: full_refund)
          {
            submitted: result.ok?
          }
        end

        # Public: Send a code for support portal email verification
        # email - the email to send the code to
        # code  - the code to send
        # returns SendHelpHubEmailVerifiedSignInCodeResponse indicating success of queuing the email
        def send_help_hub_email_verified_sign_in_code(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "email") if req.email.blank?
          return Twirp::Error.invalid_argument("must be provided", argument: "code") if req.code.blank?

          queued = !!HelpHubEmailVerifiedSignInMailer.helphub_email_verified_sign_in_code_requested(req.email, req.code).deliver_later

          {
            enqueued: queued
          }
        end

        # Public: Implementation of the GetCopilotAdministrativeBlockStatus Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::GetCopilotAdministrativeBlockStatus.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a Hash suitable for use in a
        # MonolithTwirp::Support::HelpHub::V1::GetCopilotAdministrativeBlockResponse.
        def get_copilot_administrative_block_status(req, env)
          user_id = id_argument(req.user_id)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id") unless user_id

          user = User.find_by(id: user_id)
          return Twirp::Error.not_found("user does not exist", argument: "user_id") unless user

          copilot_user = Copilot::User.new(user)

          active_block = Copilot::AdministrativeBlock.active.where(blockable: copilot_user).order("created_at DESC").first

          {
            administrative_block: copilot_user.administrative_blocked?,
            block_reason: active_block ? "Blocked by #{active_block.actor} with reason: #{active_block.reason}" : ""
          }
        end

        # Public: Implementation of the GetUsedProducts Twirp RPC.
        #
        # Returns a list of product names that the user has used based on their user ID.
        #
        # req - The Twirp request as MonolithTwirp::Support::HelpHub::V1::GetUsedProductsRequest.
        # env - The Twirp environment as a Hash.
        #
        # MonolithTwirp::Support::HelpHub::V1::GetUsedProductsResponse with used products.
        def get_used_products(req, env)
          user_id = id_argument(req.user_id)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id") unless user_id

          user = User.find_by(id: user_id)
          return Twirp::Error.not_found("user does not exist", argument: "user_id") unless user

          if req.products.empty?
            return Twirp::Error.invalid_argument("no products specified", argument: "products")
          end

          used_products = req.products.select do |product_name|
            has_product_usage?(user, product_name)
          end

          {
            products: used_products.map do |product_name|
              {
                name: product_name
              }
            end
          }
        end

        private

        # Private: Returns Users for each of the given user IDs.
        #
        # ids - User IDs in a Google::Protobuf::RepeatedField
        #
        # Returns an ActiveRecord::Relation of User, or a Twirp::Error.
        def get_users_by_id(ids, argument_name:, limit:)
          if ids.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: argument_name)
          end

          if ids.size > limit
            return Twirp::Error.invalid_argument("must have a length <= #{limit}",
              argument: argument_name)
          end

          # ids is a Google::Protobuf::RepeatedField, and we need to call #to_a to get a value
          # usable by ActiveRecord:
          User.where(id: ids.to_a)
        end

        # Private: Convert an array of User objects to the shape Twirp responses expect.
        #
        # users - The array of User objects.
        #
        # Returns an array of Hash objects with user data that matches the
        # Twirp definition.
        def build_user_list(users)
          users.map do |user|
            build_user_result(user)
          end
        end

        # Private: Returns a hash for constructing a UserListItem.
        #
        # user - User record
        def build_user_result(user)
          spammy_parser = ::Spam::SpammyReasonNormalizer.new(user.spammy_reason)
          {
            id: user.id,
            login: user.login,
            name: user.safe_profile_name,
            avatar_url: user.primary_avatar_url,
            profile_url: "#{GitHub.url}/#{user.path}",
            email: build_user_email(user),
            is_site_admin: user.site_admin?,
            type: user_type_enum(user),
            has_two_factor_authentication_enabled: user.two_factor_authentication_enabled?,
            plan_name: user.plan.name,
            verified_emails: build_user_verified_emails_result(user),
            is_spammy: user.spammy?,
            is_suspended: user.suspended?,
            spamurai_classification: spamurai_classification(user),
            # Don't send new global_ids here until receivers are ready for it (see https://github.com/github/github/pull/173984#discussion_r597048522)
            global_relay_id: Platform::Helpers::GlobalId.for(user, user_preference: false, user_opt_out: true),
            created_at: Google::Protobuf::Timestamp.new(seconds: user.created_at.to_i),
            analytics_tracking_id: user.analytics_tracking_id,
            spammy_detail: {
              analyst: spammy_parser.analyst,
              classifier_type: spammy_parser.classifier_type,
              classifier_id: spammy_parser.classifier_id,
              subject: spammy_parser.subject,
              spammy_reason: user.spammy_reason
            }
        }
        end

        # Private: Returns a hash for constructing a UserVerifiedEmailsResultItem.
        #
        # user - User record
        def build_user_verified_emails_result(user)
          # mannequin's do not have verified emails
          return nil if user.mannequin?

          # For enterprise managed users, return just the single profile_email
          if user.is_enterprise_managed?
            return [{
              email: user.profile_email,
              is_primary: true,
              visibility: :EMAIL_VISIBILITY_PRIVATE,
              claimed: user.primary_user_email&.claimed?
            }]
          end

          user.emails.verified.map do |email|
            {
              email: email.email,
              is_primary: email.primary?,
              visibility: get_email_visibility(email)
            }
          end
        end

        # Private: Returns email for user, stripping shortcode in case they are Enterprise Managed
        def build_user_email(user)
          user.is_enterprise_managed? ? user.profile_email : user.email
        end

        # Private: Convert an array of Organization objects to Twirp UserOrganizationsInfoResultItem
        #
        # organizations - The array of Organization objects.
        #
        # Returns an array of Hash objects that matches the Twirp UserOrganizationsInfoResultItem definition.
        def build_organizations_info_list(all_organizations, user)
          GitHub::PrefillAssociations.prefill_batch_method(all_organizations, :coupon_redemption)
          all_organizations.map do |org|
            {
              id: org.id,
              name: org.name,
              plan: org.plan.name,
              seats: org.seats,
              filled_seats: 1,
              is_verified: org.is_verified?,
              roles: org.role_of(user).types.map(&:to_s),
              enterprise_id: org&.business&.id,
              profile_name: org.profile_name,
              coupon_code: org.coupon_redemption&.coupon&.code,
              verified_domains: VerifiableDomain.where(owner: org, verified: true).limit(100).map(&:domain),
              coupon_expires_at: org.coupon_redemption&.expires_at&.utc&.strftime("%Y-%m-%dT%H:%M:%SZ"),
              avatar_url: org.primary_avatar_url,
            }
          end
        end

        # Private: Convert an array of User objects to Twirp UserBillingInfoResultItem
        #
        # users - The array of User objects.
        #
        # Returns an array of Hash objects with user id and billing info that matches the
        # Twirp UserBillingInfoResultItem definition.
        def build_billing_info_list(users)
          GitHub::PrefillAssociations.prefill_batch_method(users, :coupon_redemption)
          users.map do |user|
            coupon_redemption = user.coupon_redemption
            {
              user_id: user.id,
              coupon_code: coupon_redemption&.coupon&.code,
              coupon_expires_at: coupon_redemption&.expires_at&.utc&.strftime("%Y-%m-%dT%H:%M:%SZ"),
              is_paying_off_plan: user.help_hub_eligibility.eligible_based_on_usage_products?,
              downgradable_products: user.help_hub_eligibility.helphub_downgradable_products,
            }
          end
        end

        def user_type_enum(user)
          case user
          when Organization
            :USER_TYPE_ORGANIZATION
          when Bot
            :USER_TYPE_BOT
          when Mannequin
            :USER_TYPE_MANNEQUIN
          when User
            :USER_TYPE_USER
          else
            :USER_TYPE_INVALID
          end
        end

        def spamurai_classification(user)
          if user.spammy?
            :SPAMURAI_CLASSIFICATION_SPAMMY
          elsif user.hammy?
            :SPAMURAI_CLASSIFICATION_HAMMY
          else
            :SPAMURAI_CLASSIFICATION_INVALID
          end
        end

        def get_email_visibility(user_email)
          if user_email.public?
            :EMAIL_VISIBILITY_PUBLIC
          elsif user_email.private?
            :EMAIL_VISIBILITY_PRIVATE
          else
            :EMAIL_VISIBILITY_INVALID
          end
        end
      end
    end
  end
end
