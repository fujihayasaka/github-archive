# typed: true
# frozen_string_literal: true

require "monolith-twirp-elm-issues"

module Api::Internal::Twirp::Elm
  module Issues
    module V1
      # Handler for the MonolithTwirp::Elm::Issues::V1::ExportIssueEventsAPIService
      class ExportIssueEventsAPIHandler < Api::Internal::Twirp::Handler
        DEFAULT_PER_PAGE = 100 # Default number of items per page for pagination

        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]
        handles_service MonolithTwirp::Elm::Issues::V1::ExportIssueEventsAPIService

        # Public: Implementation of the ExportIssueEvents Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Elm::Issues::V1::ExportIssueEventsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Elm::Issues::V1::ExportIssueEventsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Elm::Issues::V1::ExportIssueEventsRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Elm::Issues::V1::ExportIssueEventsResponse, Twirp::Error))
        end
        def export_issue_events(req, env)
          repo_id = req.repository_id
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") if repo_id == 0

          repository = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
            T.cast(::Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
          else
            Repository.find_by(id: repo_id)
          end
          if repository.nil?
            return Twirp::Error.not_found("Repository not found", argument: "repository_id").tap do |error|
              error.meta[:value] = repo_id.to_s
              error.meta[:elm_error_code] = "REPOSITORY_NOT_FOUND"
            end
          elsif repository.deleted?
            return Twirp::Error.not_found("Repository deleted", argument: "repository_id").tap do |error|
              error.meta[:value] = repo_id.to_s
              error.meta[:elm_error_code] = "REPOSITORY_DELETED"
            end
          end

          build_issue_events_response(repository, req)
        end

        sig do
          params(
            repository: Repository,
            req: MonolithTwirp::Elm::Issues::V1::ExportIssueEventsRequest,
          ).returns(MonolithTwirp::Elm::Issues::V1::ExportIssueEventsResponse)
        end
        def build_issue_events_response(repository, req)
          repository_id = repository.id
          page = req.page.zero? ? 1 : req.page

          per_page = req.per_page.zero? ? DEFAULT_PER_PAGE : req.per_page
          pagination = GH::Pagination::Offset.new(page:, per_page:)
          # we are paginating with an offset collection, and we want access
          # to the total_entries, which is not defined on all collections.
          collection = T.cast(
            IssueEvents::Public.for_export(pagination:, repository_id:),
            GH::Domain::OffsetCollection[IssueEvent]
          )

          issue_numbers_by_id = ::Issues.domain.numbers_by_ids(repository_id, collection.map(&:issue_id).uniq)
          is_pull_request_by_id = ::Issues.domain.is_pull_request_by_ids(collection.map(&:issue_id).uniq)

          MonolithTwirp::Elm::Issues::V1::ExportIssueEventsResponse.new(
            success: true,
            total_count: collection.total_entries,
            export_issue_events: collection.map do |issue_event|
              build_api_issue_event(
                issue_event,
                repository:,
                issue_number: T.must(issue_numbers_by_id[issue_event.issue_id]),
                is_pull_request: is_pull_request_by_id[issue_event.issue_id] || false,
              )
            end
          )
        end

        sig do
          params(
            issue_event: IssueEvent,
            repository: Repository,
            issue_number: Integer,
            is_pull_request: T::Boolean,
          ).returns(MonolithTwirp::Elm::Issues::V1::ExportIssueEvent)
        end
        def build_api_issue_event(issue_event, repository:, issue_number:, is_pull_request:)
          url_path = if is_pull_request
            "/#{repository.owner_display_login}/#{repository.name}/pull/#{issue_number}"
          else
            "/#{repository.owner_display_login}/#{repository.name}/issues/#{issue_number}"
          end
          event_url_path = "#{url_path}#event-#{issue_event.id}"

          event_args = {
            url: "#{GitHub.url}#{event_url_path}",
            actor_url: GitHub::Resources::UrlForModel.new(issue_event.actor).url,
            event: issue_event.event,
            created_at: Google::Protobuf::Timestamp.new(seconds: issue_event.created_at.to_i),
          }

          event_args[:pull_request_url] = "#{GitHub.url}#{url_path}" if is_pull_request
          event_args[:issue_url] = "#{GitHub.url}#{url_path}" if !is_pull_request

          MonolithTwirp::Elm::Issues::V1::ExportIssueEvent.new(**event_args)
        end
      end
    end
  end
end
