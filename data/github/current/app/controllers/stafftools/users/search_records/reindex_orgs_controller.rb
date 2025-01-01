# typed: true
# frozen_string_literal: true

class Stafftools::Users::SearchRecords::ReindexOrgsController < StafftoolsController
  before_action :ensure_org_not_user
  before_action :ensure_user_exists

  def create
    this_user.searchable_repos.each do |repo|
      repo.reindex_all
    end

    redirect_to stafftools_user_search_record_path(this_user), notice: "Reindex job was enqueued."
  end
end
