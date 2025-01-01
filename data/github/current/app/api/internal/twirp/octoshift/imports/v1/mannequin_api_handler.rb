# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Provides access to Mannequin data.
      class MannequinAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay

        handles_service MonolithTwirp::Octoshift::Imports::V1::MannequinAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]
        connected_to_writing_for :create_mannequin
        BATCH_SIZE = 1000

        # Public: Implementation of the FindMannequin Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::FindMannequinRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::FindMannequinResponse, or a Twirp::Error.
        def find_mannequin(req, env)
          if req.source_login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "source_login")
          end
          if req.owner_id.zero?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "owner_id")
          end

          owner = replica(User).find_by(id: req.owner_id)
          return Twirp::Error.not_found("Owner '#{req.owner_id}' was not found.") unless owner

          truncated_source_login = truncate_source_login(req.source_login)

          # Not sure how to address this (or any has_many_through) in a performant way because a where clause
          # will delay the find and I believe this endpoint is called frequently
          mannequin = owner.mannequins.find_by(source_login: truncated_source_login)

          return Twirp::Error.not_found("Mannequin associated with source_login '#{req.source_login}' was not found.") unless mannequin

          {
            mannequin: build_mannequin_hash(mannequin)
          }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Public: Implementation of the FetchOwnerMannequins Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::FetchOwnerMannequinsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::FetchOwnerMannequinsResponse, or a Twirp::Error.
        def fetch_owner_mannequins(req, env)
          if req.owner_id.zero?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "owner_id")
          end

          owner = replica(User).find_by(id: req.owner_id)
          return Twirp::Error.not_found("Owner '#{req.owner_id}' was not found.") unless owner

          mannequins = owner.mannequins
          mannequin_ids = mannequins.pluck(:id)
          mannequin_claimants = {}

          # Get all the claimants for the mannequins. We do this due to a has_many_through relationship
          mannequin_ids.each_slice(BATCH_SIZE) do |mannequin_batch_ids|
            replica(Mannequin).query do |klass|
              klass.where(id: mannequin_batch_ids).joins(:claimant).pluck("users.id", "users.login", "users.source_login", "claimants_users.display_login").each do |mannequin_id, login, source_login, claimant_login|
                mannequin_claimants[mannequin_id] = {
                  login: login,
                  source_login: source_login,
                  claimant_login: claimant_login,
                }
              end
            end
          end

          mannequin_hashes = mannequins.map do |mannequin|
            {
              id: mannequin.id,
              login: mannequin.login,
              source_login: mannequin.source_login,
              claimant_login: mannequin_claimants[mannequin.id].present? ? mannequin_claimants[mannequin.id][:claimant_login] : nil,
            }
          end

          {
            mannequins: mannequin_hashes
          }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Public: Implementation of the CreateMannequin Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::CreateMannequinRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::CreateMannequinResponse, or a Twirp::Error.
        def create_mannequin(req, env)
          if req.source_login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "source_login")
          end
          if req.owner_id.zero?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "owner_id")
          end

          owner = replica(User).find_by(id: req.owner_id)
          return Twirp::Error.not_found("Owner '#{req.owner_id}' was not found.") unless owner

          return already_exists_error_handler("Mannequin") if replica(Mannequin).query do |klass|
            klass.joins(:mannequin_ownership).where(
              "source_login" => req.source_login,
              "mannequin_ownership.owner_id" => owner.id
            ).exists?
          end

          truncated_source_login = truncate_source_login(req.source_login)

          mannequin = T.let(nil, T.nilable(Mannequin))
          twirp_error = T.let(nil, T.untyped)
          Mannequin.transaction do
            mannequin = Mannequin.new(
              source_login: truncated_source_login,
              owner: owner
            )
            unless mannequin.save
              twirp_error = save_model_error_handler(mannequin)
              raise ActiveRecord::Rollback
            end

            if req.profile_name.present?
              unless mannequin.update(profile_name: req.profile_name)
                twirp_error = save_model_error_handler(mannequin)
                raise ActiveRecord::Rollback
              end
            end

            if req.email.present?
              mannequin_email = MannequinEmail.new(
                mannequin: mannequin,
                email: req.email,
                primary: true
              )
              unless mannequin_email.save
                twirp_error = save_model_error_handler(mannequin_email)
                raise ActiveRecord::Rollback
              end
            end
          end
          return twirp_error if twirp_error.present?

          {
            mannequin: build_mannequin_hash(mannequin)
          }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def build_mannequin_hash(mannequin)
          {
            id: mannequin.id,
            login: mannequin.login,
            source_login: mannequin.source_login,
            claimant_login: mannequin.claimant_login,
            profile_name: mannequin.profile_name
          }
        end

        def truncate_source_login(source_login)
          source_login.truncate(User::LOGIN_MAX_LENGTH)
        end
      end
    end
  end
end
