# typed: true
# frozen_string_literal: true

require "monolith-twirp-mailreplies-replies"

module Api::Internal::Twirp::MailReplies
  module Replies
    module V1
      # Handler for the MonolithTwirp::MailReplies::Replies::V1::RepliesAPIService,
      # used by the mail-replies service to submit parsed emails for processing
      # as replies or unsubscribe requests.
      class RepliesAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["mail_replies"]
        handles_service MonolithTwirp::MailReplies::Replies::V1::RepliesAPIService

        # The Tenant Context resolution is done inside the enqueued Email*Job instances
        exempt_from_tenant_context_requirement

        # Public: Implementation of the SubmitEmailReply Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::MailReplies::Replies::V1::SubmitEmailReplyRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::MailReplies::Replies::V1::SubmitEmailReplyResponse, or a Twirp::Error.
        def submit_email_reply(req, env)
          EmailReplyJob.perform_later req.email.to_h.deep_stringify_keys
          {}
        end

        # Public: Implementation of the SubmitEmailUnsubscribe Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::MailReplies::Replies::V1::SubmitEmailUnsubscribeRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::MailReplies::Replies::V1::SubmitEmailUnsubscribeResponse, or a Twirp::Error.
        def submit_email_unsubscribe(req, env)
          EmailUnsubscribeJob.perform_later req.email.to_h.deep_stringify_keys
          {}
        end
      end
    end
  end
end
