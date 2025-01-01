# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      class ImportReleaseAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::Attribution

        allow_access_for :client, allowed_clients: %w[octoshift migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportReleaseAPIService

        RELEASE_STATE_MAP = {
          RELEASE_STATE_PUBLISHED: :published,
          RELEASE_STATE_DRAFT: :draft,
        }.freeze
        MAX_THROTTLE_RETRIES = 5.freeze

        # Public: Implementation of the ImportRelease Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportReleaseRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportReleaseResponse, or a Twirp::Error.
        def import_release(req, env)
          check_model_replication_delay!(ImportableRelease)

          # validations of required params
          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          if req.author_login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "author_login")
          end

          user = find_mannequin_or_user_by_login(req.author_login)
          unless user
            return Twirp::Error.not_found("User not found.", argument: "author_login", value: req.author_login.to_s)
          end

          if req.tag_name.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "tag_name")
          end

          if req.state == :RELEASE_STATE_INVALID
            return Twirp::Error.invalid_argument("must be non-empty", argument: "state")
          end

          if req.created_at.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "created_at")
          end

          release = ImportableRelease.new(
            repository: repository,
            author: user,
            name: req.name,
            tag_name: req.tag_name,
            state: RELEASE_STATE_MAP[req.state],
            pending_tag: req.pending_tag,
            created_at: req.created_at.to_time,
            body: req.body,
          )

          if req.published_at.present? && req.state == :RELEASE_STATE_PUBLISHED
            release.published_at = req.published_at.to_time
          end

          release.prerelease = req.is_pre_release
          release.target_commitish = req.target_commitish unless req.target_commitish.empty?

          Release.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, skip_reporting: true) do
            ActiveRecord::Base.connected_to(role: :writing) do
              unless release.save
                return Twirp::Error.canceled("Could not create release: #{release.errors.full_messages.join(", ")}")
              end
            end
          end

          {
            release: {
              id: release.id,
            }
          }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end
      end
    end
  end
end
