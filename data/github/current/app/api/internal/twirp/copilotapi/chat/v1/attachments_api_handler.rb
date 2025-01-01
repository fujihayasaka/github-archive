# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilotapi-chat"

module Api::Internal::Twirp::Copilotapi
  module Chat
    module V1
      # Handler for the MonolithTwirp::Copilotapi::Chat::V1::AttachmentsAPIService
      class AttachmentsAPIHandler < Api::Internal::Twirp::Handler

        allow_access_for :client, allowed_clients: ["copilot_api"]
        handles_service MonolithTwirp::Copilotapi::Chat::V1::AttachmentsAPIService

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::GetSignedAttachmentUrlsRequest,
            env: Hash
          ).returns(T.any(Hash, Twirp::Error))
        end
        def get_signed_attachment_urls(req, env)
          return Twirp::Error.invalid_argument("attachments is empty") if req.attachments.blank?
          attachments = []

          user = ::User.find_by(id: req.user_id)
          return Twirp::Error.not_found("user not found") if user.nil?

          copilot_user = Copilot::Public::User.new(user)
          return Twirp::Error.not_found("user does not have copilot access") unless copilot_user.has_copilot_access?

          req.attachments.each do |a|
            policy_model = Storage.policy_creator.for(a.type)
            return Twirp::Error.invalid_argument("invalid attachment type") if policy_model.nil?

            attachment = policy_model.model.find_by(id: a.id)

            return Twirp::Error.not_found("attachment not found") unless attachment && user_allowed?(attachment, user)

            attachments << {
              id: attachment.id,
              type: policy_model.model.uploadable_policy_path,
              signed_url: attachment.storage_policy.download_url,
            }
          end

          {
            attachments: attachments
          }
        end

        # This is T.untyped for now in anticipation of other copilot attachable
        # types in the future.
        sig do
          params(
            attachment: T.untyped,
            user: User
          ).returns(T::Boolean)
        end
        def user_allowed?(attachment, user)
          case attachment
          when Copilot::ChatAttachment
            attachment.uploader == user
          else
            false
          end
        end
      end
    end
  end
end
