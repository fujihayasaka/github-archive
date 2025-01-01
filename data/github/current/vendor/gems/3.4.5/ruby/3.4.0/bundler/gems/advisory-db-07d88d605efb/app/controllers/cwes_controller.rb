# frozen_string_literal: true

class CWEsController < InboxController
  def index
    filtered_cwes = CWE.in_numeric_order.limit(10)
    filtered_cwes = filtered_cwes.with_content_like(params[:q]) if params[:q].present?

    render partial: "advisories/cwe_autocomplete_items", locals: { cwes: filtered_cwes.pluck(:cwe_id, :name) }
  end
end
