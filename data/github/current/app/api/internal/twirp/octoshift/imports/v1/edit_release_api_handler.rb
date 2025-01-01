# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditReleaseAPIService
      class EditReleaseAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::Attribution
        include Imports::Helpers::ContentCreation
        include Imports::Helpers::LiveMigrations
        include Imports::Helpers::ModelDelay
        include Helpers::ErrorHandler

        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::EditReleaseAPIService

        RELEASE_STATE_MAP = {
          EDIT_RELEASE_STATE_PUBLISHED: :published,
          EDIT_RELEASE_STATE_DRAFT: :draft,
        }.freeze

        # Public: Implementation of the EditRelease Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditReleaseRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Octoshift::Imports::V1::EditReleaseResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Octoshift::Imports::V1::EditReleaseRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Octoshift::Imports::V1::EditReleaseResponse, Twirp::Error))
        end
        def edit_release(req, env)
          check_model_replication_delay!(ImportableRelease)

          # Validate the request
          err = validate(req)
          return err if err

          # Fetch the user who edited the release
          user = user_or_ghost(req.author_login)
          return Twirp::Error.not_found("User '#{req.author_login}' was not found.") unless user

          # Fetch the release to edit
          release = replica(ImportableRelease).find_by(id: req.id)
          return Twirp::Error.not_found("Release not found.", argument: "id", value: req.id.to_s, octoshift_error_code: "RELEASE_NOT_FOUND") if release.nil?

          # Only update if the incoming updated_at is newer than the latest timestamp on the
          # release
          err = check_outdated_updated_at(release, req.updated_at)
          return err if err

          rate_limited_mode(release) do
            if req.action == :LIVE_MIGRATION_ACTION_EDITED
              return edit(release, req, user)
            elsif req.action == :LIVE_MIGRATION_ACTION_DELETED
              return delete(release)
            end
          end
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        sig do
          params(
            release: ImportableRelease,
            req: MonolithTwirp::Octoshift::Imports::V1::EditReleaseRequest,
            user: T.nilable(User)
          ).returns(T.any(MonolithTwirp::Octoshift::Imports::V1::EditReleaseResponse, Twirp::Error))
        end
        def edit(release, req, user)
          # Update the release attributes
          release.author = user unless user.nil?
          release.name = req.name unless req.name.empty?
          release.tag_name = req.tag_name unless req.tag_name.empty?
          release.state = RELEASE_STATE_MAP[req.state] if req.state != :EDIT_RELEASE_STATE_INVALID
          release.pending_tag = req.pending_tag unless req.pending_tag.empty?
          release.body = req.body&.value unless req.body.nil? || req.body&.value&.empty?
          release.updated_at = T.must(req.updated_at).to_time
          release.prerelease = req.is_pre_release

          # Save the changes
          if release.save
            MonolithTwirp::Octoshift::Imports::V1::EditReleaseResponse.new(id: release.id)
          else
            Twirp::Error.internal("Failed to save the release changes.")
          end
        end

        sig do
          params(
            release: ImportableRelease,
          ).returns(T.any(MonolithTwirp::Octoshift::Imports::V1::EditReleaseResponse, Twirp::Error))
        end
        def delete(release)
          # Deletion is not yet supported; erturn an error.
          Twirp::Error.canceled("Release deletion is not supported at this time")
        end

        sig { params(req: MonolithTwirp::Octoshift::Imports::V1::EditReleaseRequest).returns(T.nilable(Twirp::Error)) }
        def validate(req)
          unless req.id.positive?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "id")
          end

          if req.action == :LIVE_MIGRATION_ACTION_INVALID
            return Twirp::Error.invalid_argument("must be a valid action", argument: "action")
          end

          if req.updated_at.nil?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "updated_at")
          end

          if req.action == :LIVE_MIGRATION_ACTION_EDITED
            # at least one of the properties must be non-protobuf-nil
            if req.author_login.blank? &&
               req.name.blank? &&
               req.tag_name.blank? &&
               req.state == :EDIT_RELEASE_STATE_INVALID &&
               req.pending_tag.blank? &&
               req.body.blank?

              Twirp::Error.invalid_argument("at least one of author_login, name, tag_name, state, pending_tag, or body must be provided", argument: "action")
            end
          end
        end
      end
    end
  end
end
