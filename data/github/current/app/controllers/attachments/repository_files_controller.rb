# typed: true
# frozen_string_literal: true

class Attachments::RepositoryFilesController < ApplicationController
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
    return render_404 unless repository_file
    return render_404 unless repository.public? || repository.readable_by?(current_user)

    repository_file.download
    redirect_to repository_file.redirect_url(actor: current_user)
  end

  private

  memoize def repository_file
    RepositoryFile.where(
      id: params[:id],
      name: params[:path],
      state: 1, # uploaded
    ).first

  end

  memoize def repository
    repository_file.repository if repository_file
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless repository # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    repository.owner
  end
end
