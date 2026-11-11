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
          # Bulk-resolve subject URL/number per event
          subjects_by_event_id = resolve_subjects(repository_id, collection)

          MonolithTwirp::Elm::Issues::V1::ExportIssueEventsResponse.new(
            success: true,
            total_count: collection.total_entries,
            export_issue_events: collection.map do |issue_event|
              build_api_issue_event(
                issue_event,
                repository:,
                issue_number: T.must(issue_numbers_by_id[issue_event.issue_id]),
                is_pull_request: is_pull_request_by_id[issue_event.issue_id] || false,
                subject: subjects_by_event_id[issue_event.id],
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
            subject: T.nilable(T::Hash[Symbol, T.untyped]),
          ).returns(MonolithTwirp::Elm::Issues::V1::ExportIssueEvent)
        end
        def build_api_issue_event(issue_event, repository:, issue_number:, is_pull_request:, subject:)
          url_path = if is_pull_request
            "/#{repository.owner_display_login}/#{repository.name}/pull/#{issue_number}"
          else
            "/#{repository.owner_display_login}/#{repository.name}/issues/#{issue_number}"
          end
          event_url_path = "#{url_path}#event-#{issue_event.id}"
          actor = issue_event.actor

          event_args = {
            url: "#{GitHub.url}#{event_url_path}",
            actor_url: actor.nil? ? "" : actor_url_for_issue_event_actor(actor),
            event: issue_event.event,
            created_at: Google::Protobuf::Timestamp.new(seconds: issue_event.created_at.to_i),
            issue_event_metadata_json: build_issue_event_metadata_json(issue_event, subject:),
          }

          event_args[:pull_request_url] = "#{GitHub.url}#{url_path}" if is_pull_request
          event_args[:issue_url] = "#{GitHub.url}#{url_path}" if !is_pull_request

          MonolithTwirp::Elm::Issues::V1::ExportIssueEvent.new(**event_args)
        end

        sig do
          params(
            issue_event: IssueEvent,
            subject: T.nilable(T::Hash[Symbol, T.untyped]),
          ).returns(String)
        end
        def build_issue_event_metadata_json(issue_event, subject:)
          base = Api::Serializer.serialize(:issue_event_detail, issue_event) || {}
          if subject
            base[:subject_url]    = subject[:url]    if subject[:url]
            base[:subject_number] = subject[:number] if subject[:number]
          end
          base[:commit_id] = issue_event.commit_id if issue_event.commit_id.present?
          if issue_event.event.in?(%w[milestoned demilestoned]) && (detail = issue_event.issue_event_detail)
            base[:milestone_id] = detail.milestone_id if detail.milestone_id
            base[:milestone_title] = detail.milestone_title if detail.milestone_title.present?
          end
          # For review_dismissed events
          if issue_event.issue_event_detail&.pull_request_review_id
            base[:pull_request_review_id] = issue_event.issue_event_detail.pull_request_review_id
          end
          base.to_json
        end

        sig { params(actor: User).returns(String) }
        def actor_url_for_issue_event_actor(actor)
          return actor.permalink if actor.is_a?(Bot)
          GitHub::Resources::UrlForModel.new(actor).url
        rescue ActionController::UrlGenerationError
          # Fallback if route generation fails for an otherwise valid actor.
          "#{GitHub.url}/#{actor.display_login}"
        end

        # Bulk-resolves issue event subjects into { url: } (User/Bot) or
        # { number: } (Issue/PullRequest/Project).
        sig do
          params(repo_id: Integer, collection: T::Enumerable[IssueEvent])
            .returns(T::Hash[Integer, T::Hash[Symbol, T.untyped]])
        end
        def resolve_subjects(repo_id, collection)
          subject_refs = collection.filter_map do |ie|
            d = ie.issue_event_detail
            next unless d && d.subject_id
            [ie.id, d.subject_type || "User", d.subject_id]
          end
          return {} if subject_refs.empty?

          grouped = subject_refs.group_by { |t| t[1] }

          user_ids = (grouped["User"] || []).map { |t| t[2] }
          user_rows = if user_ids.empty?
            {}
          else
            ::User.where(id: user_ids).pluck(:id, :login, :type).to_h { |id, login, type| [id, { login:, type: }] }
          end

          bot_ids = user_rows.select { |_, v| v[:type] == "Bot" }.keys
          bots_by_id = if bot_ids.empty?
            {}
          else
            # Preload integration + owner so bot.permalink doesn't hit the DB per bot.
            ::Bot.where(id: bot_ids).includes(integration: :owner).index_by(&:id)
          end

          issue_ids   = (grouped["Issue"]       || []).map { |t| t[2] }
          pr_ids      = (grouped["PullRequest"] || []).map { |t| t[2] }
          project_ids = (grouped["Project"]     || []).map { |t| t[2] }

          issue_nums = issue_ids.empty? ? {} : ::Issues.domain.numbers_by_ids(repo_id, issue_ids)

          pr_nums = if pr_ids.empty?
            {}
          else
            ::Issue.where(repository_id: repo_id, pull_request_id: pr_ids).pluck(:pull_request_id, :number).to_h # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          end

          proj_nums = if project_ids.empty?
            {}
          else
            ::Project.where(owner_id: repo_id, owner_type: "Repository", id: project_ids).pluck(:id, :number).to_h # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          end

          subject_refs.each_with_object({}) do |(event_id, type, id), out|
            case type
            when "User"
              row = user_rows[id] or next
              if row[:type] == "Bot"
                bot = bots_by_id[id] or next
                out[event_id] = { url: bot.permalink }
              else
                out[event_id] = { url: "#{GitHub.url}/#{row[:login]}" }
              end
            when "Issue"
              out[event_id] = { number: issue_nums[id] } if issue_nums[id]
            when "PullRequest"
              out[event_id] = { number: pr_nums[id] } if pr_nums[id]
            when "Project"
              out[event_id] = { number: proj_nums[id] } if proj_nums[id]
            end
            # Skip Team, IssueComment, PRReviewPoint which aren't imported.
          end
        end
      end
    end
  end
end
