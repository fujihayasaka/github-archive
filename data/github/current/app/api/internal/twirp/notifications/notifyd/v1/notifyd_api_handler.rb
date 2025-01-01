# typed: true
# frozen_string_literal: true

require "monolith-twirp-notifications-notifyd"

module Api::Internal::Twirp::Notifications
  module Notifyd
    module V1
      # Handler for the MonolithTwirp::Notifications::Notifyd::V1::MobileAPIService
      # The following implementation performs delivery checks to verify whether a notification should be delivered or not.
      # This implementation is temporary. In the long term, the goal is to migrate these checks into notifyd.
      # To know more check: https://github.com/github/notifyd/blob/main/docs/adr/0015-make-requests-to-the-monolith-for-mobile-push-checks-during-the-migration-to-notifyd.md
      class NotifydAPIHandler < Api::Internal::Twirp::Handler
        include GitHub::Tracing

        MAX_BATCH_SIZE = 250

        allow_access_for :client, allowed_clients: ["notifyd"]
        handles_service MonolithTwirp::Notifications::Notifyd::V1::NotifydAPIService

        class UndeliverableError < StandardError; end

        def get_deliver_email_data(req, env)
          user = require_user(req)

          org_present = id_argument(req.organization_id)
          org = require_organization(req) if org_present

          settings = GitHub.newsies.settings(user).value
          email =
            if org.present?
              return { is_deliverable: false, error: "blocked by organization settings" } unless org.user_can_receive_email_notifications?(user)

              settings.email(org)&.address
            else
              settings.email(:global)&.address
            end

          if user.is_enterprise_managed? || user.emails.verified.exists?(email: email)

            result = {
              is_deliverable: !!email,
              email: email.presence,
              login: user.display_login,
            }

            result[:auth_tokens] = req.auth_token_requests.reduce([]) do |auth_tokens, request|
              # Protobuf::Map is not automatically unpacked to hash
              payload = request.data.to_h
              token = auth_token(user, request.scope, payload)

              next auth_tokens unless token.present?
              auth_tokens.push({ scope: request.scope, token: token })
            end

            return result
          end

          { is_deliverable: false, error: "user email not verified" }
        rescue UndeliverableError => e
          {
            is_deliverable: false,
            error: e.message
          }
        end

        # Public: Implementation of the CheckDeliverMobilePushPolicy Twirp RPC.
        #         It verifies if notification can be delivered by checking the mobile push policy:
        #           - User is allowing to receive notifications by notification type (settings)
        #           - User is allowing to receive notifications by schedule
        #           - User is not blocked by saml restrictions
        #           - Author user is not blocked by recipient user
        #
        # req - The Twirp request as a MonolithTwirp::Notifications::Notifyd::V1::CheckDeliverMobilePushRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Notifications::Notifyd:V1::CheckDeliverMobilePushPolicyResponse
        #   E.g. { is_deliverable: true } or { is_deliverable: false, error: "blocked by settings" }
        #
        def check_deliver_mobile_push_policy(req, env)
          require_oauth_access(req.oauth_access_id) if req.reasons == ["mobile_auth_request"]

          user = require_user(req)

          raise UndeliverableError.new("blocked by missing active mobile auth") unless oauth_access_token_has_active_mobile_auth?(user.id, req.oauth_access_id, req.reasons)
          raise UndeliverableError.new("blocked by settings") unless allowed_by_settings?(user, req.reasons)
          raise UndeliverableError.new("blocked by schedule") unless allowed_by_schedule?(user, req.reasons)

          unless req.skip_saml_enforcement
            org = require_organization(req)

            raise UndeliverableError.new("blocked by saml restrictions") unless allowed_by_saml_restrictions?(user, org, req.oauth_access_id)
          end

          {
            is_deliverable: true,
            login: user.display_login
          }
        rescue UndeliverableError => e
          {
            is_deliverable: false,
            error: e.message
          }
        end

        # Public: Implementation of the BatchCheckNotifyPolicy Twirp RPC.
        #         It verifies if notification should be delivered to recipients by checking:
        #           - Notification actor is not a spammy user
        #           - Recipient user is not suspended (Check skipped if reason for notification is mobile_auth_request)
        #           - Recipient user is not a bot
        #           - Recipient user is not an organization
        #           - Recipient user is not ignoring the repository
        #
        # req - The Twirp request as a MonolithTwirp::Notifications::Notifyd::V1::BatchCheckNotifyPolicyRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Notifications::Notifyd:V1::BatchCheckNotifyPolicyResponse, or a Twirp::Error.
        # Response value is a list of hashes detailing whether recipient can be notified or not and the possible error.
        #   E.g. [{ user_id: 1, notify: true },
        #         { user_id: 2, notify: false, error: "actor is spammy" }]
        #
        #
        trace_method :batch_check_notify_policy
        def batch_check_notify_policy(req, env)
          # ActiveRecord cannot handle this as a Google::Protobuf::RepeatedField
          user_ids = req.recipients.map(&:user_id)

          if user_ids.length > MAX_BATCH_SIZE
            return Twirp::Error.invalid_argument("Too many user_ids in list, max: #{MAX_BATCH_SIZE}", argument: "user_ids")
          end

          return { responses: [] } if user_ids.empty?

          actor = User.find_by(id: req.context.actor_id)
          if actor.present? && actor.spammy?
            responses = user_ids.map { |id| { user_id: id, notify: false, error: "actor is spammy" } }
            return { responses: responses }
          end

          batch_check(req, env, actor, user_ids)
        end

        # Public: Implementation of the BatchCheckIgnoredRepository Twirp RPC.
        #         It verifies if notification should be delivered to recipients by checking:
        #           - Recipient user is not ignoring the repository
        #
        # req - The Twirp request as a MonolithTwirp::Notifications::Notifyd::V1::BatchCheckIgnoredRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Notifications::Notifyd:V1::BatchCheckIgnoredRepositoryResponse, or a Twirp::Error.
        # Response value is a list of hashes detailing whether recipient can be notified or not and the possible error.
        # Example:
        #  [
        #    { user_id: 1, notify: true },
        #    { user_id: 2, notify: false, error: "ignoring repository" },
        #  ]
        #
        trace_method :batch_check_ignored_repository
        def batch_check_ignored_repository(req, env)
          repository_id = req.repository_id&.value
          return Twirp::Error.invalid_argument("Missing repository ID", argument: "repository_id") unless repository_id.present?

          unless Repository.active.select(:id).find_by(id: repository_id)
            return Twirp::Error.invalid_argument("Repository not found", argument: "repository_id")
          end

          return { responses: [] } if req.recipients.empty?

          if req.recipients.length > MAX_BATCH_SIZE
            return Twirp::Error.invalid_argument("Too many recipients in list, max: #{MAX_BATCH_SIZE}", argument: "recipients")
          end

          # ActiveRecord cannot handle this as a Google::Protobuf::RepeatedField
          user_ids = req.recipients.map(&:user_id)

          ignoring_user_ids = Newsies::ListSubscription
            .for_list(Newsies::List.new("Repository", repository_id))
            .where(user_id: user_ids)
            .only_ignored
            .pluck(:user_id)
            .to_set

          responses = user_ids.map do |user_id|
            if ignoring_user_ids.include?(user_id)
              { user_id: user_id, notify: false, error: "ignoring repository" }
            else
              { user_id: user_id, notify: true }
            end
          end

          { responses: responses }
        end

        def post_process_email_content(req, env)
          unless req.raw_html.present?
            return Twirp::Error.invalid_argument("Missing raw_html argument", argument: "raw_html")
          end
          head_index = req.raw_html.index("</head>")
          unless head_index.present?
            return Twirp::Error.invalid_argument("Raw_html should contain head tags", argument: "raw_html")
          end

          { processed_html: inline_styles(req.raw_html) }
        end

        private

        trace_method :inline_styles
        def inline_styles(html)
          premailer = Premailer.new(html,
            with_html_string: true,
            drop_unmergeable_css_rules: true,
            preserve_style_attribute: true,
            output_encoding: "US-ASCII",
            input_encoding: "UTF-8",
            remove_scripts: false,
            adapter: :nokogiri_fast,
            css: MailerBundleHelper.primer_email_stylesheet_uris
          )
          # Using T.unsafe to bypass Sorbet's type check for Premailer method
          T.unsafe(premailer).to_inline_css
        end

        def require_user(req)
          user_id = id_argument(req.user_id)
          raise UndeliverableError.new("user_id missing") unless user_id

          user = User.find_by(id: user_id)
          raise UndeliverableError.new("user not found") unless user.present?

          user
        end

        def require_organization(req)
          organization_id = id_argument(req.organization_id)
          raise UndeliverableError.new("organization_id is required unless skip_saml_restrictions is true") unless organization_id

          organization = Organization.find_by(id: organization_id)
          raise UndeliverableError.new("organization not found") unless organization.present?
          organization
        end

        def require_oauth_access(oauth_access_id)
          oauth_access_id = id_argument(oauth_access_id)
          raise UndeliverableError.new("oauth_access_id is required") unless oauth_access_id

          oauth_access = OauthAccessTokens.domain.by_id(oauth_access_id)
          raise UndeliverableError.new("oauth_access not found") unless oauth_access
          oauth_access
        end

        def allowed_by_settings?(user, reasons)
          return true if reasons == ["mobile_auth_request"]

          # TODO: (@franciscoj 30/11/2022) this setting is managed and stored
          # by notifyd. If the notification has been matched and routed by
          # notifyd it means the right setting has already been taken into
          # account. That's why we early return `true`.
          #
          # The rest of the checks we do here are legacy and need to be little
          # by little moved to notifyd and transform in early returns like this
          # one until this callback can be removed.
          return true if reasons.include?("ci_activity")
          if GitHub.flipper[:notifyd_release_notify].enabled?(user)
            return true if reasons.include?("list_subscription")
            return true if reasons.include?("thread_type_subscription")
          end

          settings = MobilePushNotificationSetting.find_by(user_id: user.id)
          return false unless settings.present?

          reasons.any? do |reason|
            case reason
            when "mention"
              settings.direct_mentions?
            when "pull_request_reviewed"
              settings.pull_request_reviews?
            when "assign"
              settings.assignments?
            when "review_requested"
              settings.review_requests?
            when "approval_requested"
              settings.deployment_requests?
            else
              false
            end
          end
        end

        def allowed_by_schedule?(user, reasons)
          return true if reasons == ["mobile_auth_request"]

          Newsies::MobilePushNotificationSchedule.deliver_to_user?(user)
        end

        def is_unavailable_error(err)
          err.respond_to?(:twirp_error) && err&.twirp_error&.code == :unavailable
        end

        def oauth_access_token_has_active_mobile_auth?(user_id, oauth_access_id, reasons)
          return true unless reasons == ["mobile_auth_request"]

          mdm = ::GitHub::Authnd.mobile_device_manager("github/notifyd")
          response = mdm.find_active_device_auth(user_id, oauth_access_id)
          response.success? && response.has_valid_device_key
        rescue ::Authnd::Proto::Error, Faraday::Error => err
          ::Notifyd::NotifydFailbot.report!(err) unless is_unavailable_error(err)
          raise UndeliverableError.new("unable to determine if the device is available for the push notification")
        end

        def allowed_by_saml_restrictions?(user, organization, oauth_access_id)
          return true unless Organization::SamlEnforcementPolicy.new(
            organization: organization,
            user: user
          ).enforced?

          oauth_access = require_oauth_access(oauth_access_id)

          Organization::CredentialAuthorization.authorization(organization: organization, credential: oauth_access).present?
        end

        trace_method :batch_check
        def batch_check(req, env, actor, user_ids)
          users = User.where(id: user_ids)
          subject_owner = User.find_by(id: req.context&.owner_id&.value)

          # TODO: We get the list of users ignoring the repository from
          # newsies. This is a temporary workaround and we will eventually find
          # a way to own this data.
          ignores_idx =
            if req.context.repository_id&.value.present?
              Newsies::ListSubscription
                .for_list(Newsies::List.new("Repository", req.context.repository_id.value))
                .where(user_id: user_ids)
                .only_ignored
                .pluck(:user_id)
                .map { |id| [id, true] }
                .to_h
            else
              {}
            end

          # We build an index of recipients to get their reasons if we need to
          recipients_idx = req.recipients.map { |recipient| [recipient.user_id, recipient] }.to_h

          responses = users.find_each.map do |user|
            user_id = user.id

            # Make sure that suspended users have access to 2FA
            reason_names = recipients_idx[user_id]&.reasons&.map(&:name) || []
            if !reason_names.include?("mobile_auth_request") && user.suspended?
              next { user_id: user_id, notify: false, error: "user is suspended" }
            end

            # Bots and orgs do not receive notifications
            if user.bot?
              next { user_id: user_id, notify: false, error: "user is a bot" }
            end

            if user.organization?
              next { user_id: user_id, notify: false, error: "user is an organization" }
            end

            # Make sure that the owner of the subject isn't blocked/ignored by
            # the recipient or is otherwise a bad actor.
            if subject_owner.present? && user.avoid?(subject_owner)
              next { user_id: user_id, notify: false, error: "entity owner is blocked by recipient user" }
            end

            # Make sure that the actor isn't blocked/ignored by the recipient
            # or is otherwise a bad actor.
            if user.avoid?(actor)
              next { user_id: user_id, notify: false, error: "actor is blocked by recipient user" }
            end

            # Make sure that the recipient isn't ignoring the repository
            #
            # TODO: This is a temporary check and will eventually be moved to notifyd instead.
            if ignores_idx[user_id]
              next { user_id: user_id, notify: false, error: "ignoring repository" }
            end

            # If no checks have failed, we can notify that recipient.
            { user_id: user_id, notify: true }
          end

          { responses: responses }
        end

        def auth_token(user, action, data)
          case action
          when "EmailReply"
            ::Notifyd::ReplyToToken.new(user, data["notification_id"]).generate
          else
            ::Notifyd::UnsubscribeToken.new(action).sign(user, data)
          end
        end
      end
    end
  end
end
