# typed: true
# frozen_string_literal: true

class Api::Staff::AuditLog < Api::Staff::App

  before do
    deliver_error! 404 unless GitHub.enterprise?
  end

  # Get audit log results
  get "/staff/audit_log/", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/audit_log"
    results = audit_log_results(params[:phrase], per_page: params[:per_page], page: params[:page])
    flattend_results = []
    # flatten the :data key
    results.each do |r|
      flattend_results << (flatten_payload(r))
    end

    deliver_raw(flattend_results, status: 200)
  end

  private

  # flattens the payload by pulling up nested :data elements
  # We do this to keep the API responses consistent with the
  # AuditLog API
  def flatten_payload(payload)
    payload.each_with_object({}) do |(k, v), h|
      if k.to_sym == :data
        h.merge!(v)
      else
        h[k] = v
      end
    end
  end
end
