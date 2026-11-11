# typed: true
# frozen_string_literal: true

class FundingLinksController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    only: [:show]

  def show
    respond_to do |format|
      format.html do
        return render_404 if !request.xhr? && params[:fragment].to_s != "1"
        render Repositories::FundingLinksComponent.new(
          repository: current_repository,
          current_user_can_push: current_user_can_push?,
          in_overlay: true,
        ), layout: false
      end
    end
  end
end
