# typed: strict
# frozen_string_literal: true

class Api::CliInternal < Api::App
  sig { returns(T::Boolean) }
  def cli_internal_access_allowed?
    app = current_user&.oauth_access&.application
    Apps::Privileged.capable?(:access_cli_internal, app:) || \
      (app.present? && app.id == Apps::Privileged.integration_id(:codespaces_production))
  end

  sig { returns(T::Hash[String, T.nilable(String)]) }
  def auth_log_context
    oauth_access = current_user&.oauth_access
    return {} if oauth_access.nil?
    {
      "gh.oauth_access.type" => oauth_access.application_type,
      "gh.oauth_access.application.id" => oauth_access.application&.id,
      "gh.oauth_access.application.name" => oauth_access.application&.name,
    }
  end

  get "/repositories/:repository_id/cli_internal/pulls/stacks", operation_id: "cli-internal/list-pull-request-stacks", read_from_replicas: true do
    repo = find_repo!

    unless FeatureFlag.vexi.enabled?(:pull_request_stacks, repo, default: false)
      deliver_error!(404)
    end

    unless cli_internal_access_allowed?
      GitHub.logger.info(
        "Pull Request stack list access denied: wrong app",
        auth_log_context,
      )
      deliver_error!(404)
    end

    control_access :list_pull_request_stacks,
      repo:,
      enforce_oauth_app_policy: repo.private?,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    # Use pluck queries to avoid loading full ActiveRecord objects. We only need
    # stack IDs and PR numbers, so two targeted queries are more efficient than
    # three loads of Stack → StackEntry → PullRequest → Issue models.
    pr_ids_by_stack_id = PullRequests::StackEntry
      .where(repository_id: repo.id)
      .order(stack_id: :asc, position: :asc)
      .pluck(:stack_id, :pull_request_id)
      .group_by(&:first)
      .transform_values { _1.map(&:last) }

    pr_numbers_by_id = Issue
      .where(pull_request_id: pr_ids_by_stack_id.values.flatten)
      .pluck(:pull_request_id, :number)
      .to_h

    result = pr_ids_by_stack_id.map do |stack_id, pr_ids|
      {
        id: stack_id,
        pull_requests: pr_ids.filter_map { pr_numbers_by_id[_1] },
      }
    end

    deliver_raw(result, status: 200)
  end

  post "/repositories/:repository_id/cli_internal/pulls/stacks", operation_id: "cli-internal/create-pull-request-stack", read_from_replicas: true do
    with_write(clusters: [ApplicationRecord::IssuesPullRequests]) do
      repo = find_repo!

      unless FeatureFlag.vexi.enabled?(:pull_request_stacks, repo, default: false)
        deliver_error!(404)
      end

      unless cli_internal_access_allowed?
        GitHub.logger.info(
          "Pull Request stack creation access denied: wrong app",
          auth_log_context,
        )
        deliver_error!(404)
      end

      control_access :create_pull_request_stack,
        repo:,
        enforce_oauth_app_policy: repo.private?,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      data = receive_with_openapi
      pull_request_numbers = data["pull_request_numbers"]

      issues = repo.issues.where(number: pull_request_numbers).includes(:pull_request)
      pulls_by_number = issues.each_with_object({}) do |issue, h|
        pull = issue.pull_request
        h[issue.number] = pull unless pull.nil?
      end

      missing = pull_request_numbers.reject { |n| pulls_by_number.key?(n) }
      if missing.any?
        deliver_error!(404, message: "Pull requests not found: #{missing.join(", ")}")
      end

      ordered_pulls = pull_request_numbers.map { |n| pulls_by_number.fetch(n) }

      result = PullRequests::Stacks.create(ordered_pulls, actor: current_user)

      case result
      when PullRequests::Stack
        deliver_raw({ id: result.id }, status: 201)
      when PullRequests::Stacks::Error
        deliver_error!(422, message: result.message)
      else
        T.absurd(result)
      end
    end
  end

  put "/repositories/:repository_id/cli_internal/pulls/stacks/:stack_id", operation_id: "cli-internal/update-pull-request-stack", read_from_replicas: true do
    with_write(clusters: [ApplicationRecord::IssuesPullRequests]) do
      repo = find_repo!

      unless FeatureFlag.vexi.enabled?(:pull_request_stacks, repo, default: false)
        deliver_error!(404)
      end

      unless cli_internal_access_allowed?
        GitHub.logger.info(
          "Pull Request stack update access denied: wrong app",
          auth_log_context,
        )
        deliver_error!(404)
      end

      control_access :update_pull_request_stack,
        repo:,
        enforce_oauth_app_policy: repo.private?,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      stack = PullRequests::Stack.find_by(id: params[:stack_id], repository_id: repo.id)
      deliver_error!(404) unless stack

      data = receive_with_openapi
      pull_request_numbers = data["pull_request_numbers"]

      issues = repo.issues.where(number: pull_request_numbers).includes(:pull_request)
      pulls_by_number = issues.each_with_object({}) do |issue, h|
        pull = issue.pull_request
        h[issue.number] = pull unless pull.nil?
      end

      missing = pull_request_numbers.reject { |n| pulls_by_number.key?(n) }
      if missing.any?
        deliver_error!(404, message: "Pull requests not found: #{missing.join(", ")}")
      end

      ordered_pulls = pull_request_numbers.map { |n| pulls_by_number.fetch(n) }

      result = PullRequests::Stacks.lock!(stack, ttl: 10) do
        stack.reload
        PullRequests::Stacks.update_pulls(stack, ordered_pulls, actor: current_user)
      end

      case result
      when PullRequests::Stacks::Error
        deliver_error!(result.http_status, message: result.message)
      when PullRequests::Stacks::UpdatePulls::Service::Success
        deliver_raw({ id: stack.id }, status: 200)
      else
        T.absurd(result)
      end
    end
  end

  delete "/repositories/:repository_id/cli_internal/pulls/stacks/:stack_id", operation_id: "cli-internal/delete-pull-request-stack", read_from_replicas: true do
    with_write(clusters: [ApplicationRecord::IssuesPullRequests]) do
      repo = find_repo!

      unless FeatureFlag.vexi.enabled?(:pull_request_stacks, repo, default: false)
        deliver_error!(404)
      end

      unless cli_internal_access_allowed?
        GitHub.logger.info(
          "Pull Request stack deletion access denied: wrong app",
          auth_log_context,
        )
        deliver_error!(404)
      end

      control_access :delete_pull_request_stack,
        repo:,
        enforce_oauth_app_policy: repo.private?,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      stack = PullRequests::Stack.find_by(id: params[:stack_id], repository_id: repo.id)
      deliver_error!(404) unless stack

      begin
        PullRequests::Stacks.lock!(stack, ttl: 10) do
          stack.reload
          stack.destroy!
        end
      rescue GitHub::Restraint::UnableToLock
        deliver_error!(409, message: "Stack is currently being modified")
      rescue ActiveRecord::RecordNotFound
        deliver_error!(404)
      end

      deliver_empty status: 204
    end
  end
end
