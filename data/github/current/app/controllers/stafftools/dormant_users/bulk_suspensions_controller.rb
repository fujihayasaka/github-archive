# typed: true
# frozen_string_literal: true

class Stafftools::DormantUsers::BulkSuspensionsController < StafftoolsController
  before_action :enterprise_required

  def create
    User.suspend_dormant_users

    redirect_to stafftools_path, notice: "Dormant users queued for suspension."
  end
end
