# typed: true
# frozen_string_literal: true

module Copilot::MemoryAdminExportsActions
  extend ActiveSupport::Concern
  extend T::Helpers
  include GitHub::Memoizer

  TARGET_USER_EXPORT_RATE_LIMIT_MAX = 10
  TARGET_USER_EXPORT_RATE_LIMIT_TTL = 1.hour

  abstract!

  requires_ancestor { ApplicationController }

  def create
    actor = memory_export_actor

    result = Copilot::MemoryAdminExport.create_status_result(
      owner: memory_export_owner,
      actor: actor,
      target_user: memory_export_target_user,
    )
    status = result.status

    unless Copilot::MemoryAdminExport.requested_by?(status, actor: actor)
      return render json: { error: "A Copilot Memory export already exists for this owner." }, status: :unprocessable_entity
    end

    ProcessCopilotMemoryAdminExportJob.perform_later(status.id) if result.created

    render json: export_urls_payload, status: :accepted
  end

  def show
    response.headers["Cache-Control"] = "no-store"
    status = memory_export_status

    render json: active_export_payload(status), status: active_export_http_status(status)
  end

  def download
    actor = memory_export_actor
    status = memory_export_status
    return render_404 unless status&.success?
    return render_404 unless Copilot::MemoryAdminExport.requested_by?(status, actor: actor)

    unless Copilot::MemoryAdminExport.blob_exists?(status)
      Copilot::MemoryAdminExport.download_missing_blob!(status)
      return render_404
    end

    download_url = Copilot::MemoryAdminExport.download_url(status)

    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
    Copilot::MemoryAdminExport.downloaded!(status, actor: actor)
    redirect_to download_url, allow_other_host: true
  rescue Copilot::MemoryAdminExport::Storage::Error => error
    Copilot::MemoryAdminExport.download_failed!(status, error: error) if status
    render_404
  end

  private

  sig { abstract.returns(T.any(::Business, ::Organization)) }
  def memory_export_owner; end

  sig { abstract.returns(String) }
  def memory_export_download_url; end

  sig { abstract.returns(String) }
  def memory_export_status_url; end

  sig { returns(::User) }
  def memory_export_actor
    T.must(current_user)
  end

  sig { returns(T.nilable(Copilot::MemoryAdminExportJobStatus)) }
  def memory_export_status
    status = Copilot::MemoryAdminExport.status_for(
      owner: memory_export_owner,
      target_user: memory_export_target_user,
    )
    return unless status
    return unless Copilot::MemoryAdminExport.requested_by?(status, actor: memory_export_actor)

    status
  end

  sig { returns(T::Boolean) }
  def memory_export_target_user_requested?
    params[:target_user_id].present?
  end

  sig { returns(T.nilable(::User)) }
  memoize def memory_export_target_user
    return unless memory_export_target_user_requested?
    ::User.find_by(id: params[:target_user_id])
  end

  sig { returns(T::Hash[Symbol, Integer]) }
  def memory_export_target_user_url_options
    target_user = memory_export_target_user
    return {} unless target_user

    { target_user_id: target_user.id }
  end

  sig { void }
  def resolve_memory_export_target_user
    return unless memory_export_target_user_requested?

    target_user = memory_export_target_user
    return render_404 unless target_user
    return if Copilot::MemoryAdminExport.target_user_allowed?(owner: memory_export_owner, target_user: target_user)

    render_404
  end

  sig { returns(T::Boolean) }
  def creating_new_memory_export?
    Copilot::MemoryAdminExport.status_for(
      owner: memory_export_owner,
      target_user: memory_export_target_user,
    ).nil?
  end

  sig { returns(String) }
  def memory_export_rate_limit_key
    owner = memory_export_owner
    "copilot_memory_admin_exports:create:#{Copilot::MemoryAdminExport.owner_type_for(owner).underscore}:#{owner.id}"
  end

  sig { void }
  def memory_export_rate_limited
    render(
      json: { error: "Too many Copilot Memory export requests. Please try again later." },
      status: :too_many_requests
    )
  end

  sig { returns(T::Hash[Symbol, String]) }
  def export_urls_payload
    {
      jobStatusUrl: memory_export_status_url,
      downloadExportUrl: memory_export_download_url,
    }
  end

  sig { params(status: T.nilable(Copilot::MemoryAdminExportJobStatus)).returns(Symbol) }
  def active_export_http_status(status)
    return :ok unless status
    return :accepted if status.queued? || status.started?
    return :ok if status.success?

    :internal_server_error
  end

  sig { params(status: T.nilable(Copilot::MemoryAdminExportJobStatus)).returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
  def active_export_payload(status)
    return { state: "none" } unless status

    payload = {
      state: status.state,
      jobStatusUrl: memory_export_status_url,
    }
    if status.success?
      payload[:downloadExportUrl] = memory_export_download_url
    elsif status.error?
      payload[:error] = status.error_message.to_s
    end
    payload
  end
end
