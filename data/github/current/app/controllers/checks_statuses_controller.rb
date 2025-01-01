# typed: true
# frozen_string_literal: true

class ChecksStatusesController < AbstractRepositoryController
  include AvatarHelper
  include StatusHelper
  include OauthHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:rollup]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Billing,
    only: [:rollups]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:details]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:rollup, :rollups, :details],
    optional: true

  CONDITIONAL_ACCESS_BYPASS_PUBLIC_REPO_ACTIONS = %w(details rollup rollups).freeze
  ALLOWED_RENDER_LOCALS = %w(dropdown_direction disable_live_updates)

  def rollup # rubocop:todo GitHub/UseRestfulActions
    begin
      commit = current_repository.commits.find(params[:ref])
    rescue GitRPC::ObjectMissing, RepositoryObjectsCollection::InvalidObjectId
      render_404 and return
    end

    return head :ok unless commit.status_check_rollup

    # The icon view adds the default "e", but this prevents potential confusion by defining it here too
    direction = ::DropdownHelper::DROPDOWN_DIRECTIONS.key?(params[:direction]&.to_sym) ? params[:direction] : "e"
    disable_live_updates = params[:disable_live_updates]

    respond_to do |format|
      format.html_fragment do
        render partial: "statuses/icon", formats: :html, locals: {
          status: commit.status_check_rollup,
          dropdown_direction: direction,
          updatable_url: !disable_live_updates && checks_statuses_rollup_path(ref: commit.oid)
        }
      end
      format.html do
        render partial: "statuses/icon", formats: :html, locals: {
          status: commit.status_check_rollup,
          dropdown_direction: direction,
          updatable_url: checks_statuses_rollup_path(ref: commit.oid)
        }
      end
    end
  end

  def rollups # rubocop:todo GitHub/UseRestfulActions
    inputs = params.require(:items).permit!.to_h
    keyed_contents = ActiveRecord::Base.connected_to(role: :reading) do
      keyed_combined_statuses = load_combined_statuses_from_inputs(inputs)
      keyed_combined_statuses.each_with_object({}) do |(key, combined_status), contents|
        contents[key] = render_status_icon(combined_status, locals: inputs[key].slice(*ALLOWED_RENDER_LOCALS))
      end
    end

    respond_to do |format|
      format.json do
        render json: keyed_contents
      end
    end
  end

  def details # rubocop:todo GitHub/UseRestfulActions
    begin
      commit = current_repository.commits.find(params[:ref])
    rescue GitRPC::ObjectMissing, RepositoryObjectsCollection::InvalidObjectId
      render_404 and return
    end

    Commit.prefill_combined_statuses([commit], current_repository)
    view = create_view_model(Statuses::CombinedStatusView, {
      combined_status: commit.combined_status,
      simple_view: true,
      popover: params[:popover].present?,
    })

    respond_to do |format|
      format.json do
        check_runs = view.sorted_statuses.map do |status|
          if status.application
            avatar_url = status.application.url
            avatar_description = "#{status.application.name} (@#{status.application.user.display_login}) generated this status."
            avatar_logo = oauth_application_logo_url status.application
            avatar_background_color = "##{status.application.preferred_bgcolor}"
          elsif status.creator
            avatar_url = user_path(status.creator)
            avatar_description = "@#{status.creator.display_login.chomp('[bot]')} generated this status."
            avatar_logo = avatar_url_for status.creator
            avatar_background_color = "#ffffff"
          end

          {}.tap do |opts|
            opts[:state]              = status.state
            opts[:description]        = status.description || default_status_check_description(status.state)
            opts[:target_url]         = status.target_url
            opts[:name]               = status.contextual_name
            opts[:icon]               = icon_symbol_for_state(status.state)
            opts[:avatar_url]         = avatar_url
            opts[:avatar_description] = avatar_description
            opts[:avatar_logo]        = avatar_logo
            opts[:avatar_background_color] = avatar_background_color
            opts[:additional_context] = additional_status_check_context(status.state, status.duration_in_seconds)
            opts[:pending]            = status_check_pending?(status.state)
          end
        end

        # TODO How is this different from statusRollup, the state used for the icon before opening the rollup?
        state = if view.all_succeeded?
          "SUCCEEDED"
        elsif view.all_failing?
          "FAILED"
        elsif view.pending?
          "PENDING"
        else
          "UNSUCCESSFUL"
        end

        result = {
          check_runs: check_runs,
          checks_header_state: state,
          checks_status_summary: view.checks_status_summary,
        }

        result = result.deep_transform_keys { |key| key.to_s.camelize(:lower) }

        render json: result
      end
      format.html_fragment do
        render partial: "statuses/combined_branch_status", formats: :html, locals: { view: view }
      end
      format.html do
        render partial: "statuses/combined_branch_status", formats: :html, locals: { view: view }
      end
    end
  end

  private

  ## modified from RepositoryObjectsCollection#verify_sha_format
  def invalid_sha_format(sha)
    !sha.is_a?(String) || sha =~ /[^a-fA-F0-9]/
  end

  def load_combined_statuses_from_inputs(inputs)
    object_promises = inputs.map do |(key, item)|
      commit_oid = item["oid"]
      GitHub.tracer.in_span("checks/checks_statuses_controller#load_combined_statuses_from_inputs", kind: :internal, attributes: { "commit_oid" => commit_oid }) do
        if invalid_sha_format(commit_oid)
          GitHub.dogstats.increment("checks_statuses_invalid_sha")
          next [key, nil]
        end

        Platform::Loaders::CombinedStatusOverview.load(current_repository, commit_oid)
        .then do |rows|
          states = rows.map { |row| row["conclusion"] }
          state = ::StatusCheckRollup.rollup_state(states)
          short_text = Platform::Loaders::CombinedStatusOverview.short_text(rows)
          next [key, nil] if short_text.nil?

          combined_status = ::CombinedStatus.new(current_repository, commit_oid, platform_type_name: "StatusCheckRollup", state: state, short_text: short_text)
          [key, combined_status]
        end
      end
    end

    Promise.all(object_promises).sync.to_h
  end

  def render_status_icon(combined_status, locals: {})
    return "" unless combined_status

    # Rubocop really doesn't like this line even though we use
    # a string literal for `partial` and we use `render_to_string`
    # elsewhere with no issues.
    #
    # rubocop:disable GitHub/RailsControllerRenderLiteral
    render_to_string(
      partial: "statuses/icon",
      formats: [:html],
      locals: locals.merge({
        status: combined_status,
        updatable_url: checks_statuses_rollup_path(ref: combined_status.sha)
      })
    )
  end

  def route_supports_advisory_workspaces?
    action_name == "rollups"
  end
end
