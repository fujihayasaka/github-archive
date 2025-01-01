# frozen_string_literal: true

class ValidationsController < InboxController
  def cve_id
    value = params[:value]

    if !AdvisoryDBToolkit::CVEIDValidator.valid?(value)
      render plain: "CVE ID is invalid.",
        status: :unprocessable_entity
    elsif CVEReview.exists?(assigned_cve_id: value)
      render plain: "#{value} is already assigned.",
        status: :unprocessable_entity
    else
      head :ok
    end
  end

  def replaced_by_cve_id
    value = params[:value]

    if AdvisoryDBToolkit::CVEIDValidator.valid?(value)
      head :ok
    else
      render plain: "CVE ID is invalid.",
        status: :unprocessable_entity
    end
  end
end
