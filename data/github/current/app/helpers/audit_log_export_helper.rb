# typed: true
# frozen_string_literal: true

# Shared logic for exporting audit logs in controllers
module AuditLogExportHelper
  extend T::Helpers
  requires_ancestor { ApplicationController }

  # Writes an audit_log export range (partial or complete) to the http response for downloading.
  # Exports are stored in chunks of data. All the chunks combined represent a complete export.
  # A single export might be split into multiple downloads consisting of a number of different chunks.
  # Parameters:
  # export - AuditLogWebExport or AuditLogGitEvent export object
  # options - hash [required]
  #   start: index of the export chunk to start with. Defaults to 0 aka the first chunk.
  #   length: number of chunks to export. Defaults to -1 aka all.
  def render_audit_log_export_range(export, options)
    start_index = 0
    end_index = 0
    length = -1

    if options
      start_index = options[:start]&.to_i || 0
      length = options[:length]&.to_i || -1
    end

    if length < 1 || length > export.total_chunks
      length = export.total_chunks
    end

    if start_index < 0 || start_index > export.total_chunks
      return render_404
    end

    end_index = start_index + length - 1
    if end_index > export.total_chunks
      end_index = export.total_chunks - 1
    end

    response.headers["Content-Disposition"] = "attachment; filename=\"#{export.human_filename(start_index)}\""

    content_length = 0
    content = []
    (start_index..end_index).each do |index|
      chunk = export.remote_object.fetch(index)
      content_length += chunk.length
      content << chunk
    end

    response.headers["Content-Length"] = content_length.to_s
    self.response_body = content
  end

  # Writes an audit_log export to the http response for downloading.
  # Exports are stored in chunks of data. All the chunks combined represent a complete export.
  # A single export might be split into multiple downloads consisting of a number of different chunks.
  # Parameters:
  # export - AuditLogWebExport or AuditLogGitEvent export object
  # options - hash defaults to nil. Not passing options will export all chunks.
  #   start: index of the export chunk to start with. Defaults to 0 aka the first chunk.
  #   length: number of chunks to export. Defaults to -1 aka all.
  def render_audit_log_export(export, options = nil)
    return render_404 unless export.remote_object?

    GitHub.dogstats.increment("audit_log_export", tags: ["action:download"])

    response.headers["Content-Type"] = export.content_type
    response.headers["Last-Modified"] = export.created_at.ctime

    if options && options.length > 0
      render_audit_log_export_range(export, options)
    else
      response.headers["Content-Length"] = export.remote_object.size.to_s
      response.headers["Content-Disposition"] = "attachment; filename=\"#{export.human_filename}\""
      self.response_body = Enumerator.new do |output|
        export.remote_object.get do |chunk|
          output << chunk
        end
      end
    end
  end

  def respond_with_audit_log_export(export:, export_url:, status_url: nil, verify_url: nil)
    respond_to do |format|
      format.json do
        if export.persisted?
          body = {
            export_url: export_url,
            status_url: !status_url.nil? ? status_url : job_status_url(export),
          }
          body[:verify_url] = verify_url unless verify_url.nil?

          render json: body, status: 201
        elsif !export.errors[:subject].empty?
          head 429
        else
          render nothing: true, status: 400
        end
      end

      format.all do
        render_404
      end
    end
  end

  def respond_with_audit_log_export_status(export)
    if export.persisted?
      export_status = export.get_and_sync_status
      status = case export_status
      when :STATUS_TYPE_SUCCESSFUL
        200
      when :STATUS_TYPE_STARTED
        202
      else
        500
      end
      head status
    else
      render nothing: true, status: 400
    end
  end

  def respond_with_audit_log_truncate_status(export)
    respond_to do |format|
      format.json do
        if export.persisted?
          body = {
            truncated: export.results_truncated?,
          }

          render json: body, status: 200
        else
          render nothing: true, status: 400
        end
      end

      format.all do
        render_404
      end
    end
  end

end
