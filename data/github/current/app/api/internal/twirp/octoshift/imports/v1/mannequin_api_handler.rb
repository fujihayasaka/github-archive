# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Provides access to Mannequin data.
      class MannequinAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelAvailability
        include Imports::Helpers::AlreadyExists

        handles_service MonolithTwirp::Octoshift::Imports::V1::MannequinAPIService
        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]
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
        rescue Api::Internal::Twirp::Octoshift::Errors::DatastoreUnavailableForWrites => error
          datastore_unavailable_for_writes_error_handler(error.role)
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

          # Get all the claimants for the mannequins.
          mannequin_ids.each_slice(BATCH_SIZE) do |mannequin_batch_ids|
            # Fetch claim mappings: mannequin_id -> claimant_id
            claims = replica(MannequinClaim).query do |klass|
              klass.where(mannequin_id: mannequin_batch_ids).pluck(:mannequin_id, :claimant_id)
            end
            claimant_id_by_mannequin_id = claims.to_h

            # Load claimant display logins by id
            claimant_ids = claimant_id_by_mannequin_id.values.compact.uniq
            claimant_logins_by_id = if claimant_ids.any?
              replica(User).query do |klass|
                klass.where(id: claimant_ids).pluck(:id, :display_login).to_h
              end
            else
              {}
            end

            # Fetch mannequin login/source_login for this batch
            mannequin_source_logins = replica(Mannequin).query do |klass|
              klass.where(id: mannequin_batch_ids).pluck(:id, :login, :source_login)
            end

            # Combine results
            mannequin_source_logins.each do |mannequin_id, login, source_login|
              claimant_id = claimant_id_by_mannequin_id[mannequin_id]
              next unless claimant_id

              mannequin_claimants[mannequin_id] = {
                login: login,
                source_login: source_login,
                claimant_login: claimant_logins_by_id[claimant_id],
              }
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
        rescue Api::Internal::Twirp::Octoshift::Errors::DatastoreUnavailableForWrites => error
          datastore_unavailable_for_writes_error_handler(error.role)
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

          if Mannequin.break_joins_enabled?
            existing_mannequin_ids = MannequinOwnership.where(owner_id: req.owner_id).pluck(:mannequin_id)
            check_for_existing_record!(
              Mannequin,
              source_login: req.source_login,
              id: existing_mannequin_ids
            )
          else
            check_for_existing_record!(
              Mannequin,
              source_login: req.source_login,
              "mannequin_ownership.owner_id": req.owner_id,
              joins: [:mannequin_ownership]
            )
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
              unless mannequin.update(display_name: req.profile_name)
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
        rescue Api::Internal::Twirp::Octoshift::Errors::AlreadyExists => error
          error.to_twirp_error
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        rescue Api::Internal::Twirp::Octoshift::Errors::DatastoreUnavailableForWrites => error
          datastore_unavailable_for_writes_error_handler(error.role)
        end

        private

        def build_mannequin_hash(mannequin)
          {
            id: mannequin.id,
            login: mannequin.login,
            source_login: mannequin.source_login,
            claimant_login: mannequin.claimant_login,
            profile_name: mannequin.display_name
          }
        end

        def truncate_source_login(source_login)
          source_login.truncate(User::LOGIN_MAX_LENGTH)
        end
      end
    end
  end
end
