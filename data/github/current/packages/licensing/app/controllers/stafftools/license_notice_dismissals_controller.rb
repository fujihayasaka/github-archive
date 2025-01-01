# typed: true
# frozen_string_literal: true

class Stafftools::LicenseNoticeDismissalsController < StafftoolsController
  before_action :enterprise_required
  skip_before_action :sudo_filter

  def create
    expires = params[:ttl] ? params[:ttl].to_i.seconds.from_now : nil
    enterprise_license.hide_warning(current_user, params[:type], expires: expires)

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end
end
