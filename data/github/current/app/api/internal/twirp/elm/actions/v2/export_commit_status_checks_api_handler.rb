# typed: strict
# frozen_string_literal: true

require "base64"
require "monolith-twirp-elm-actions"

module Api::Internal::Twirp::Elm
  module Actions
    module V2
      class ExportCommitStatusChecksAPIHandler < Api::Internal::Twirp::Handler
        class InvalidPageToken < StandardError; end

        # context is part of the keyset so the query can use
        # index_statuses_on_repository_id_and_created_at_and_context instead of filesorting.
        class Cursor < T::Struct
          const :created_at_after, T.nilable(Time)
          const :context_after, T.nilable(String)
          const :id_after, Integer
        end

        handles_service MonolithTwirp::Elm::Actions::V2::ExportCommitStatusChecksAPIService
        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]

        sig do
          params(
            req: MonolithTwirp::Elm::Actions::V2::ExportCommitStatusChecksRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def export_commit_status_checks(req, env)
          repo_id = req.repository_id
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") if repo_id.zero?

          repository = resolve_repository(repo_id)
          return repository_error(repo_id, "Repository not found", "REPOSITORY_NOT_FOUND") if repository.nil?
          return repository_error(repo_id, "Repository deleted", "REPOSITORY_DELETED") if repository.deleted?

          cursor = decode_cursor(req.page_token)
          return Twirp::Error.invalid_argument("must be a token returned by this API", argument: "page_token") if cursor.nil?

          # Fetch the raw page before filtering. Pagination must continue from
          # the raw page even when every status in it is filtered out.
          statuses = Statuses.domain.list_page_for_export(
            repository_id: repo_id,
            limit: per_page,
            created_at_after: cursor.created_at_after,
            context_after: cursor.context_after,
            id_after: cursor.id_after
          )

          exportable_statuses = statuses_with_existing_commits(repository, statuses)

          {
            export_commit_status_checks: exportable_statuses.map { |status| build_status_check_hash(status) },
            # Always calculate the cursor from the unfiltered database page.
            next_page_token: next_page_token_for(statuses)
          }
        end

        private

        sig { params(repo_id: Integer).returns(T.nilable(::Repositories::IRepository)) }
        def resolve_repository(repo_id)
          return ::Repositories.domain.by_id(repo_id) if FeatureFlag.vexi.enabled?(:repos_by_id_api_twirp, default: false)

          Repository.find_by(id: repo_id)
        end

        # Keeps only statuses whose OIDs currently resolve to commit objects.
        #
        # Missing objects and objects that are not commits are omitted. All
        # other Git and Spokes failures propagate.
        sig do
          params(
            repository: ::Repositories::IRepository,
            statuses: T::Array[T.untyped]
          ).returns(T::Array[T.untyped])
        end
        def statuses_with_existing_commits(repository, statuses)
          return statuses if statuses.empty?

          commit_oids = statuses.filter_map do |status|
            commit_oid = status.commit_oid
            commit_oid if commit_oid.present?
          end

          return [] if commit_oids.empty?

          available_oids = commit_availability_checker(repository)
            .available_oids(commit_oids)

          # select preserves the order of the original status page.
          statuses.select do |status|
            commit_oid = status.commit_oid
            commit_oid.present? && available_oids.include?(commit_oid.downcase)
          end
        end

        sig do
          params(repository: ::Repositories::IRepository)
            .returns(::Api::Internal::Twirp::Elm::Actions::CommitAvailabilityChecker)
        end
        def commit_availability_checker(repository)
          ::Api::Internal::Twirp::Elm::Actions::CommitAvailabilityChecker.new(
            repository: repository
          )
        end

        sig { params(repo_id: Integer, message: String, elm_error_code: String).returns(Twirp::Error) }
        def repository_error(repo_id, message, elm_error_code)
          Twirp::Error.not_found(message, argument: "repository_id").tap do |error|
            error.meta[:value] = repo_id.to_s
            error.meta[:elm_error_code] = elm_error_code
          end
        end

        # Server-chosen page size. There is no per_page field in the v2 request, so
        # the server picks the size. Defined as a method so tests can shrink it to
        # exercise multi-page walks with a handful of rows.
        sig { returns(Integer) }
        def per_page
          100
        end

        # The token is "d|<unix_seconds>|<id>|<context>"; context can contain
        # "|", so it is placed last and the token is split with a limit of 4.
        sig { params(page_token: String).returns(T.nilable(Cursor)) }
        def decode_cursor(page_token)
          return Cursor.new(created_at_after: nil, context_after: nil, id_after: 0) if page_token.blank?

          parts = base64url_decode(page_token).split("|", 4)
          raise InvalidPageToken unless parts.length == 4 && parts[0] == "d"

          Cursor.new(
            created_at_after: parse_time(parts[1]),
            context_after: parts[3],
            id_after: parse_int(parts[2])
          )
        rescue InvalidPageToken
          nil
        end

        # statuses is the private Statuses model array from the domain, so it is
        # untyped across the package boundary.
        sig { params(statuses: T::Array[T.untyped]).returns(String) }
        def next_page_token_for(statuses)
          last = statuses.last
          return "" unless statuses.length == per_page && last

          encode_dated_cursor(last.created_at.to_i, last.id, last.context)
        end

        sig { params(status: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
        def build_status_check_hash(status)
          {
            id: status.id,
            commit_sha: status.commit_oid,
            context: status.context,
            state: status.state,
            description: status.description,
            target_url: status.target_url,
            creator_id: status.creator_id,
            creator_html_url: status.creator.nil? ? "" : creator_url_for_status(status.creator),
            created_at: { seconds: status.created_at.to_i, nanos: 0 }
          }
        end

        sig { params(user: User).returns(String) }
        def creator_url_for_status(user)
          return user.permalink if user.is_a?(Bot)

          GitHub::Resources::UrlForModel.new(user).url
        rescue ActionController::UrlGenerationError
          "#{GitHub.url}/#{user.display_login}"
        end

        sig { params(unix_seconds: Integer, id: Integer, context: String).returns(String) }
        def encode_dated_cursor(unix_seconds, id, context)
          base64url_encode("d|#{unix_seconds}|#{id}|#{context}")
        end

        sig { params(value: String).returns(String) }
        def base64url_encode(value)
          Base64.urlsafe_encode64(value, padding: false)
        end

        # Decode as UTF-8 so a context value round-trips.
        sig { params(value: String).returns(String) }
        def base64url_decode(value)
          padded = value + ("=" * ((4 - (value.length % 4)) % 4))
          decoded = Base64.urlsafe_decode64(padded).force_encoding(Encoding::UTF_8)
          raise InvalidPageToken unless decoded.valid_encoding?

          decoded
        rescue ArgumentError
          raise InvalidPageToken
        end

        sig { params(value: T.nilable(String)).returns(Integer) }
        def parse_int(value)
          raise InvalidPageToken if value.nil?

          Integer(value, 10)
        rescue ArgumentError, TypeError
          raise InvalidPageToken
        end

        sig { params(value: T.nilable(String)).returns(Time) }
        def parse_time(value)
          Time.at(parse_int(value)).utc
        rescue RangeError
          raise InvalidPageToken
        end
      end
    end
  end
end
