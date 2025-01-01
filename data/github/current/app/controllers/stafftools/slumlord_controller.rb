# typed: true
# frozen_string_literal: true

class Stafftools::SlumlordController < StafftoolsController
  before_action :disable_when_unavailable
  before_action :ensure_repo_exists

  layout "layouts/stafftools/repository/storage"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    # Things to do here:
    # 1. View if SVN has been used. (fs_exist? 'svn.history.msgpack')
    # 2. Enable/disable SVN (banhammer)
    # 3. Enable/disable debugging
    # 4. Set the correct support contact for the sample error message shown

    if current_repository.online?
      @svn_in_use = current_repository.svn_in_use?
      @svn_status = current_repository.svn_status
      @svn_blocked = current_repository.svn_blocked?
      @svn_debugging = current_repository.svn_debugging?
      @support_contact = GitHub.support_link_text
    end

    render "stafftools/slumlord/show"
  end

  def toggle_blocked # rubocop:todo GitHub/UseRestfulActions
    current_repository.svn_toggle_blocked
    redirect_to :back
  rescue GitHub::DGit::UnroutedError
    flash[:error] = "Repository offline"
    redirect_to :back
  end

  def toggle_debug # rubocop:todo GitHub/UseRestfulActions
    current_repository.svn_toggle_debugging
    redirect_to :back
  rescue GitHub::DGit::UnroutedError
    flash[:error] = "Repository offline"
    redirect_to :back
  end

  def disable_when_unavailable # rubocop:todo GitHub/UseRestfulActions
    render_404 unless GitHub.svnbridge_available?
  end
end
