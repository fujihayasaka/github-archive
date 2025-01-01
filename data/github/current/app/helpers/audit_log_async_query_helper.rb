# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/RailsViewRenderLiteral

# Shared logic for stafftools audit logs async queries in controllers
module AuditLogAsyncQueryHelper
  extend T::Helpers
  requires_ancestor { StafftoolsController }
  requires_ancestor { ActionController::Head }

  def respond_with_audit_log_async_query(query:, results_url:, status_url:)
    if query.persisted?
      body = {
        results_url: results_url,
        status_url: status_url,
      }

      render json: body, status: 201
    elsif !query.errors[:actor].empty?
      head 429
    else
      render nothing: true, status: 400
    end
  end

  def respond_with_audit_log_async_query_status(query)
    if query.persisted?
      if query.is_completed?
        head 200 # completed
      else
        head 202 # in progress
      end
    else
      render nothing: true, status: 400
    end
  end
end
