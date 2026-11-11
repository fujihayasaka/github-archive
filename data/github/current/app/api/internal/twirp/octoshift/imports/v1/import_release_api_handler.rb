# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      class ImportReleaseAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelAvailability
        include Imports::Helpers::Attribution

        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportReleaseAPIService

        RELEASE_STATE_MAP = {
          RELEASE_STATE_PUBLISHED: :published,
          RELEASE_STATE_DRAFT: :draft,
        }.freeze
        MAX_THROTTLE_RETRIES = 5.freeze

        # Map of incoming make_latest enum representations to Ruby values.
        # Keys include generated enum constants (integers), symbols, and upcased strings.
        MAKE_LATEST_MAP = ActiveSupport::HashWithIndifferentAccess.new(
          {
            MonolithTwirp::Octoshift::Imports::V1::MakeLatest::MAKE_LATEST_TRUE => true,
            :MAKE_LATEST_TRUE => true,
            "MAKE_LATEST_TRUE" => true,

            MonolithTwirp::Octoshift::Imports::V1::MakeLatest::MAKE_LATEST_FALSE => false,
            :MAKE_LATEST_FALSE => false,
            "MAKE_LATEST_FALSE" => false,

            MonolithTwirp::Octoshift::Imports::V1::MakeLatest::MAKE_LATEST_LEGACY => :legacy,
            :MAKE_LATEST_LEGACY => :legacy,
            "MAKE_LATEST_LEGACY" => :legacy
          }
        ).freeze

        # Public: Implementation of the ImportRelease Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportReleaseRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportReleaseResponse, or a Twirp::Error.
        def import_release(req, env)
          check_datastore_available_for_writes!(ImportableRelease)

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

          is_draft = RELEASE_STATE_MAP[req.state] == :draft
          if req.tag_name.empty? && !is_draft
            return Twirp::Error.invalid_argument("must be non-empty", argument: "tag_name")
          end

          if req.state == :RELEASE_STATE_INVALID
            return Twirp::Error.invalid_argument("must be non-empty", argument: "state")
          end

          if req.created_at.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "created_at")
          end

          # Map Twirp MakeLatest enum values to Ruby booleans/nil so the model receives an expected value
          # Twirp protobuf enums may be deserialized as symbols (e.g. :MAKE_LATEST_TRUE),
          # strings ("MAKE_LATEST_TRUE"), or as generated enum constants (integers).
          # Use MAKE_LATEST_MAP to centralize mapping and avoid duplication.
          raw_make_latest = req.make_latest

          # Try exact lookup first (covers integer constants and symbols), then try upcased string
          make_latest_value = MAKE_LATEST_MAP[raw_make_latest]
          if make_latest_value.nil? && raw_make_latest.respond_to?(:to_s)
            make_latest_value = MAKE_LATEST_MAP[raw_make_latest.to_s.upcase]
          end

          if make_latest_value.nil? && !raw_make_latest.nil?
            Rails.logger.warn("[ImportReleaseAPI] Unexpected make_latest value: #{raw_make_latest.inspect} (class: #{raw_make_latest.class}) - defaulting to nil")
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
            make_latest: make_latest_value,
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
        rescue Api::Internal::Twirp::Octoshift::Errors::DatastoreUnavailableForWrites => error
          datastore_unavailable_for_writes_error_handler(error.role)
        end
      end
    end
  end
end
