# typed: true
# frozen_string_literal: true

class Stafftools::Users::SearchRecords::BlackbirdReindexOrgsController < StafftoolsController
  before_action :ensure_org_not_user
  before_action :ensure_user_exists

  def create
    BlackbirdOnboardJob.perform_later([this_user.login])
    redirect_to stafftools_user_search_record_path(this_user), notice: "Reindex job was enqueued."
  end
end
