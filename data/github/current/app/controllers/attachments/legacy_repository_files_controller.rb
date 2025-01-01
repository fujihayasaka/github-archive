# typed: true
# frozen_string_literal: true

class Attachments::LegacyRepositoryFilesController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    file = RepositoryFile.where(
      id: params[:id],
      name: params[:path],
      repository_id: current_repository.id,
      state: 1, # uploaded
    ).first

    return render_404 unless file
    return render_404 if file.using_new_url?

    file.download
    redirect_to file.redirect_url(actor: current_user)
  end
end
