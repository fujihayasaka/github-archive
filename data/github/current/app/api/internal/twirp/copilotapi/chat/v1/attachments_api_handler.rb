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
            if a.type == "git-blob-reference"
              raw_url = convert_github_blob_url(a.original_url, user)

              if raw_url
                attachments << {
                  original_url: a.original_url,
                  signed_url: raw_url,
                  type: a.type,
                }
              end
            elsif a.type == "legacy-reference"
              converted_url = convert_legacy_image_url(a.original_url, user)

              if converted_url
                attachments << {
                  original_url: a.original_url,
                  signed_url: converted_url,
                  type: a.type,
                }
              end
            else
              policy_model = Storage.policy_creator.for(a.type)
              return Twirp::Error.invalid_argument("invalid attachment type") if policy_model.nil?

              record = find_record(policy_model, a)
              return Twirp::Error.not_found("attachment not found") unless record && user_allowed?(user, record, a)

              attachments << {
                id: record.id,
                type: policy_model.model.uploadable_policy_path,
                signed_url: record.storage_policy.download_url,
                thread_id: a.thread_id,
                thread_shared_id: a.thread_shared_id,
                uuid: a.uuid,
              }
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
            return false if record.thread_id.present? && record.thread_id != attachment.thread_id
            record.uploader == user || attachment.thread_shared_id.present?
          when UserAsset
            return false if record.nil?
            record.has_access?(user)
          end
        end

        sig do
          params(
            policy_model: Storage::PolicyCreator::PolicyModel,
            attachment: MonolithTwirp::Copilotapi::Chat::V1::Attachment,
          ).returns(T.nilable(T.any(Copilot::ChatAttachment, UserAsset)))
        end
        def find_record(policy_model, attachment)
          model_class = policy_model.model
          if model_class == Copilot::ChatAttachment
            return Copilot::ChatAttachment.uploaded.find_by(id: attachment.id)
          end
          if model_class == UserAsset
            return UserAsset.uploaded.find_by(guid: attachment.uuid)
          end

          nil
        end
      end
    end
  end
end
