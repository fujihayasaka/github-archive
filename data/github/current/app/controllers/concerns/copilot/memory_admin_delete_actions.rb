# typed: true
# frozen_string_literal: true

module Copilot::MemoryAdminDeleteActions
  extend ActiveSupport::Concern
  extend T::Helpers
  include GitHub::Memoizer

  CREATE_RATE_LIMIT_MAX = 10
  CREATE_RATE_LIMIT_TTL = 1.hour

  abstract!

  requires_ancestor { ApplicationController }

  sig { void }
  def create
    result = Copilot::MemoryAdminDelete.create_status_result(
      owner: memory_delete_owner,
      actor: memory_delete_actor,
      target_user: memory_delete_target_user,
    )

    unless result.created
      return render json: { error: "A Copilot Memory delete is already in progress for this scope." }, status: :conflict
    end

    ProcessCopilotMemoryAdminDeleteJob.perform_later(result.status.id)
    render json: memory_delete_urls_payload, status: :accepted
  end

  sig { void }
  def show
    response.headers["Cache-Control"] = "no-store"
    status = memory_delete_status

    render json: active_memory_delete_payload(status), status: active_memory_delete_http_status(status)
  end

  private

  sig { abstract.returns(T.any(::Business, ::Organization)) }
  def memory_delete_owner; end

  sig { abstract.returns(String) }
  def memory_delete_status_url; end

  sig { returns(::User) }
  def memory_delete_actor
    T.must(current_user)
  end

  sig { returns(T.nilable(Copilot::MemoryAdminDeleteJobStatus)) }
  def memory_delete_status
    Copilot::MemoryAdminDelete.status_for(
      owner: memory_delete_owner,
      target_user: memory_delete_target_user,
    )
  end

  sig { returns(T::Boolean) }
  def memory_delete_target_user_requested?
    params[:target_user_id].present?
  end

  sig { returns(T.nilable(::User)) }
  memoize def memory_delete_target_user
    return unless memory_delete_target_user_requested?

    ::User.find_by(id: params[:target_user_id])
  end

  sig { returns(T::Hash[Symbol, Integer]) }
  def memory_delete_target_user_url_options
    target_user = memory_delete_target_user
    return {} unless target_user

    { target_user_id: target_user.id }
  end

  sig { void }
  def resolve_memory_delete_target_user
    return unless memory_delete_target_user_requested?

    target_user = memory_delete_target_user
    return render_404 unless target_user
    return if Copilot::MemoryAdminDelete.target_user_allowed?(owner: memory_delete_owner, target_user: target_user)

    render_404
  end

  sig { returns(T::Boolean) }
  def creating_new_memory_delete?
    status = memory_delete_status
    status.nil? || status.finished?
  end

  sig { returns(String) }
  def memory_delete_rate_limit_key
    owner = memory_delete_owner
    "copilot_memory_admin_deletes:create:#{Copilot::MemoryAdminDelete.owner_type_for(owner).underscore}:#{owner.id}"
  end

  sig { void }
  def memory_delete_rate_limited
    render(
      json: { error: "Too many Copilot Memory delete requests. Please try again later." },
      status: :too_many_requests
    )
  end

  sig { returns(T::Hash[Symbol, String]) }
  def memory_delete_urls_payload
    {
      jobStatusUrl: memory_delete_status_url,
    }
  end

  sig { params(status: T.nilable(Copilot::MemoryAdminDeleteJobStatus)).returns(Symbol) }
  def active_memory_delete_http_status(status)
    return :ok unless status
    return :accepted if status.queued? || status.started?
    return :ok if status.success?

    :internal_server_error
  end

  sig { params(status: T.nilable(Copilot::MemoryAdminDeleteJobStatus)).returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
  def active_memory_delete_payload(status)
    return { state: "none" } unless status

    payload = {
      state: status.state,
      jobStatusUrl: memory_delete_status_url,
    }
    payload[:error] = status.error_message.to_s if status.error?
    payload
  end
end
