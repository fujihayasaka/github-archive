# typed: true
# frozen_string_literal: true

class Stafftools::Users::SearchRecords::ReindexRequestsController < StafftoolsController
  before_action :ensure_user_exists

  def create
    this_user.calculate_primary_language!
    Search.add_to_search_index("user", this_user.id)

    redirect_to stafftools_user_search_record_path(this_user), notice: "Reindex job was enqueued."
  end
end
