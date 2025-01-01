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

          attachments_by_type = req.attachments.group_by(&:type)

          attachments_by_type.each do |type, type_attachments|
            case type
            when "git-blob-reference"
              type_attachments.each do |attachment|
                raw_url = convert_github_blob_url(attachment.original_url, user)
                if raw_url
                  attachments << {
                    original_url: attachment.original_url,
                    signed_url: raw_url,
                    type: attachment.type,
                  }
                end
              end
            when "legacy-reference"
              type_attachments.each do |attachment|
                converted_url = convert_legacy_image_url(attachment.original_url, user)
                if converted_url
                  attachments << {
                    original_url: attachment.original_url,
                    signed_url: converted_url,
                    type: attachment.type,
                  }
                end
              end
            when "copilot-chat-attachments"
              attachment_record_map = batch_find_attachments(type_attachments, Copilot::ChatAttachment)
              type_attachments.each do |attachment|
                record = attachment_record_map[attachment]
                return Twirp::Error.not_found("attachment not found") unless record && user_allowed?(user, record, attachment)

                attachments << {
                  id: record.id,
                  type: Copilot::ChatAttachment.uploadable_policy_path,
                  signed_url: record.storage_policy.download_url,
                  thread_id: attachment.thread_id,
                  thread_shared_id: attachment.thread_shared_id,
                  uuid: attachment.uuid,
                }
              end
            when "assets"
              attachment_record_map = batch_find_attachments(type_attachments, UserAsset)
              type_attachments.each do |attachment|
                record = attachment_record_map[attachment]
                return Twirp::Error.not_found("attachment not found") unless record && user_allowed?(user, record, attachment)

                attachments << {
                  id: record.id,
                  type: UserAsset.uploadable_policy_path,
                  signed_url: record.storage_policy.download_url,
                  thread_id: attachment.thread_id,
                  thread_shared_id: attachment.thread_shared_id,
                  uuid: attachment.uuid,
                }
              end
            else
              return Twirp::Error.invalid_argument("invalid attachment type")
            end
          end

          {
            attachments: attachments
          }
        end

        # Public: Implementation of the DeleteAttachmentsForThreads Twirp RPC.
        #
        # Params:
        # - req: Twirp request as a MonolithTwirp::Copilotapi::KnowledgeBases::V1::DeleteAttachmentsForThreadsRequest.
        # - env: Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::KnowledgeBases::V1::DeleteAttachmentsForThreadsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::DeleteAttachmentsForThreadsRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::Chat::V1::DeleteAttachmentsForThreadsResponse, Twirp::Error))
        end
        def delete_attachments_for_threads(req, env)
          api_method = "delete_attachments_for_threads"
          GitHub.dogstats.distribution_time("copilot.twirp.#{api_method}") do
            if !FeatureFlag.vexi.enabled?(:copilot_chat_attachments_cleanup_for_threads, default: false)
              GitHub.dogstats.increment("copilot.twirp.#{api_method}.errors", tags: ["error:feature_flag_disabled"])
              return Twirp::Error.not_found("feature flag disabled")
            end

            if req.thread_ids.blank?
              GitHub.dogstats.increment("copilot.twirp.#{api_method}.errors", tags: ["error:attachments_blank"])
              return Twirp::Error.invalid_argument("attachments is empty")
            end

            ::Copilot::ChatAttachments::CleanupForThreadsJob.perform_later(req.thread_ids.to_a)

            MonolithTwirp::Copilotapi::Chat::V1::DeleteAttachmentsForThreadsResponse.new
          end
        end

        def blob_url
          %r{
            \A
            (#{GitHub.url})? # Absolute GitHub URL, optional
            /([^/]+)         # user
            /([^/]+)         # repo
            /blob            # string literal "blob"
            /([^/]+)         # ref or branch name
            /(.*)            # treeish and path
            \z
          }x
        end

        def convert_github_blob_url(url, user)
          match = url.match(blob_url)

          return nil unless match

          name_with_owner = "#{match[2]}/#{match[3]}"
          ref = match[4]
          path = match[5]

          repository = Repository.with_name_with_owner(name_with_owner)
          return nil unless repository && repository.readable_by?(user)

          TreeEntryRenderHelper.raw_blob_url(
            user,
            repository,
            ref,
            path,
            expires_key: :blob,
          )
        end

        LEGACY_CANONICAL_URL_REGEX = %r{\A#{GitHub.url}(?::\d+)?\/[\w.-]+\/[\w.-]+\/assets\/(\d+)\/([^\.]+)\z}

        def convert_legacy_image_url(url, user)
          match = url.match(LEGACY_CANONICAL_URL_REGEX)

          return nil unless match

          user_id = match[1]
          guid = match[2]

          user_asset = UserAsset.uploaded.find_by(
            user_id: user_id,
            guid: guid,
          )

          return nil unless user_asset && user_asset.has_access?(user)

          user_asset.storage_policy.download_url
        end

        sig do
          params(
            user: User,
            record: T.any(Copilot::ChatAttachment, UserAsset), # Add new copilot attachable types here
            attachment: MonolithTwirp::Copilotapi::Chat::V1::Attachment,
          ).returns(T::Boolean)
        end
        def user_allowed?(user, record, attachment)
          case record
          when Copilot::ChatAttachment
            # Reject if attachment belongs to a different thread
            return false if record.thread_id.present? && record.thread_id != attachment.thread_id

            # Allow if user uploaded the attachment
            return true if record.uploader == user

            # Allow if attachment is shared
            return true if attachment.thread_shared_id.present?

            # Allow if attachment has no thread and user can access the associated copilot space
            if FeatureFlag.vexi.enabled?(:copilot_spaces_duplicate, user, default: false)
              copilot_space = CopilotSpace
                # Critical: only find the space if it is associated with this attachment
                .with_chat_attachment(record)
                .find_by(id: attachment.copilot_space_id)
              return true if record.thread_id.blank? && copilot_space&.readable_by?(user)
            else
              return true if record.thread_id.blank? && record.copilot_space_resources.first&.copilot_space&.readable_by?(user)
            end

            false
          when UserAsset
            return false if record.nil?
            record.has_access?(user)
          end
        end

        sig do
          params(
            attachments: T::Array[MonolithTwirp::Copilotapi::Chat::V1::Attachment],
            model_class: T.any(T.class_of(Copilot::ChatAttachment), T.class_of(UserAsset)),
          ).returns(T::Hash[MonolithTwirp::Copilotapi::Chat::V1::Attachment, T.nilable(T.any(Copilot::ChatAttachment, UserAsset))])
        end
        def batch_find_attachments(attachments, model_class)
          uuids = attachments.filter_map(&:uuid).uniq

          records_by_uuid = if uuids.any?
            model_class.uploaded.where(guid: uuids).index_by(&:guid)
          else
            {}
          end

          # Return hash with attachment objects as keys and records as values
          attachments.to_h do |attachment|
            record = attachment.uuid.present? ? records_by_uuid[attachment.uuid] : nil
            [attachment, record]
          end
        end
      end
    end
  end
end
