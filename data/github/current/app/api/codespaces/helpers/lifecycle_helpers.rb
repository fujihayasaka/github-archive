# typed: true
# frozen_string_literal: true

module Api::Codespaces::Helpers::LifecycleHelpers
  extend T::Helpers

  requires_ancestor { Api::Codespaces }

  def export_codespace(codespace, entry_point:)
    deliver_error! 422, message: Api::Codespaces::Public::EXPORT_ALREADY_UNDERWAY_MESSAGE if codespace.exporting?

    new_repository_origin = if Codespaces::RepositoryPolicy.async_with_prefill(codespace.owner, codespace.repository).sync.read_only_and_forkable?
      forked, _ = Codespaces::ForkRepo.call(codespace, codespace.export_branch_name, entry_point: entry_point)
      forked.clone_url
    end

    encrypted_github_token, key_version = Codespaces::Tokens.mint_encrypted_github_token(current_user, codespace, entry_point: entry_point)
    success = codespace.export!(
      encrypted_github_token,
      new_repository_origin: new_repository_origin,
      key_version: key_version,
      actor: current_user,
    )
    deliver_error! 422, message: Api::Codespaces::Public::CODESPACE_MUST_BE_PROVISIONED_MESSAGE unless success

    deliver :export_details_hash, { codespace: codespace }, status: 202
  rescue Codespaces::AsyncOperation::PendingError => e
    deliver_error!(422, message: e.message)
  end

  def start_codespace(codespace, entry_point:)
    set_exception_context(codespace)

    operation = begin
      Codespaces::AsyncOperation.ensure_no_blocking_pending!(codespace)
      Codespaces::AsyncOperation.create!(codespace: codespace, operation: :start_codespace)
    rescue Codespaces::AsyncOperation::PendingError => e
      # We don't want to emit a failure because of blocking pending async operation here... Feels a little weird to
      # lie like this but c'est la vie.
      request.env["codespaces.async_operation_created"] = true
      deliver_error! 422, message: e.message
    end
    request.env["codespaces.async_operation_created"] = true

    if Codespaces::Policy.codespace_user_spammy?(codespace)
      operation.mark_as_ended
      deliver_error! 403
    end
    if codespace.provisioning?
      operation.mark_as_ended
      deliver_error! 409, message: Api::Codespaces::Public::CODESPACE_STILL_PROVISIONING_MESSAGE
    end
    result = begin
      Codespaces::Start.call(codespace, user: current_user, cap_filter: cap_filter, entry_point: entry_point, operation: operation)
    rescue ActiveModel::ValidationError => e
      operation.mark_as_ended
      status = if e.model.errors.any? { |e| e.type == :billing }
        402
      elsif e.model.errors.any? { |e| e.type == :policy }
        403
      else
        422
      end
      deliver_error! status, message: "#{Api::Codespaces::CODESPACE_USAGE_DISALLOWED_MESSAGE}: #{e.model.errors.full_messages.join(" ")}"
    rescue Codespaces::Client::BadResponseError => e
      if e.unprocessable_entity?
        operation.mark_as_ended
      else
        operation.mark_as_failed(failure_reason: e.status)
        Codespaces::ErrorReporter.report(e) unless FeatureFlag.vexi.enabled?(:codespaces_automated_testing, current_user, default: false)
      end
      message, status = if e.error_codes.include?(Codespaces::VscsClient::ENVIRONMENT_NOT_SHUTDOWN_ERROR_CODE)
        [Api::Codespaces::Public::CODESPACE_ALREADY_RUNNING, 409]
      else
        [e.error_body.to_s, 400]
      end
      deliver_error! status, message:
    rescue Codespaces::ConcurrencyLimitError => e
      operation.mark_as_ended
      deliver_error! 400, message: e.message
    rescue Codespaces::CopilotWorkspaceConcurrencyLimitError => e
      operation.mark_as_ended
      deliver_error! 400, message: e.message
    rescue Codespaces::RateLimitError => e
      operation.mark_as_ended
      deliver_error! 429, message: e.message
    rescue Codespaces::CopilotWorkspaceFeatureDisabledError => e
      @codespace_async_operation&.mark_as_ended
      deliver_error! 403, message: e.message
    rescue Codespaces::AsyncOperation::PendingError => e
      operation.mark_as_ended
      deliver_error! 422, message: e.message
    rescue Codespaces::VscsClient::TierCapacityUnavailableError => e
      operation.mark_as_failed(failure_reason: e)
      Codespaces::ErrorReporter.report(e) unless FeatureFlag.vexi.enabled?(:codespaces_automated_testing, current_user, default: false)
      deliver_error! 400, message: e.message
    rescue Codespaces::Start::InaccessibleError
      operation.mark_as_ended
      deliver_error!(404)
    rescue Codespaces::Client::RequestError => e
      operation.mark_as_failed(failure_reason: e)
      raise
    rescue => e # rubocop:disable Lint/RescueException
      operation.mark_as_failed(failure_reason: e)
      raise
    end

    deliver :public_codespace_hash, { codespace: codespace }, status: result.response.status, private: FeatureFlag.vexi.enabled?(:codespaces_developer, current_user, default: false)
  end

  def stop_codespace(codespace)
    if codespace.suspendable?
      begin
        codespace.suspend!(current_user)
      rescue Codespaces::AsyncOperation::PendingError => e
        deliver_error! 422, message: e.message
      end
      deliver :public_codespace_hash, { codespace: codespace }, private: FeatureFlag.vexi.enabled?(:codespaces_developer, current_user, default: false)
    elsif codespace.suspended?
      # no-op if codespace is already suspended
      deliver :public_codespace_hash, { codespace: codespace }, private: FeatureFlag.vexi.enabled?(:codespaces_developer, current_user, default: false)
    elsif codespace.provisioning?
      deliver_error! 409, message: Api::Codespaces::Public::CODESPACE_STILL_PROVISIONING_MESSAGE if codespace.provisioning?
    else
      deliver_error! 400, message: Api::Codespaces::Public::CODESPACE_NOT_SUSPENDABLE_MESSAGE
    end
  end

end
