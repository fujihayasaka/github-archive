# typed: true
# frozen_string_literal: true

class Stafftools::AvatarsController < StafftoolsController
  before_action :ensure_user_exists

  layout :new_nav_layout
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  private def new_nav_layout
    case this_user.site_admin_context
    when "organization"
      "layouts/stafftools/organization/overview"
    when "user"
      "layouts/stafftools/user/overview"
    end
  end

  def index
    @avatar_id = params[:avatar_id].to_i
    render "stafftools/avatars/index"
  end

  def revert_to_gravatar # rubocop:todo GitHub/UseRestfulActions
    if p = this_user.primary_avatar
      p.destroy
    end
    flash[:notice] = "Reverted back to gravatar."
    redirect_to :back
  end

  def purge # rubocop:todo GitHub/UseRestfulActions
    this_user.avatar_list.purge_cdn

    instrument("avatar.purge", user: this_user)
    flash[:notice] = %(Purged "#{this_user.avatar_list.surrogate_key}".)
    redirect_to :back
  end

  def promote # rubocop:todo GitHub/UseRestfulActions
    if avatar = this_user.avatars.find_by_id(params[:id])
      PrimaryAvatar.set(avatar, avatar.uploader)
      flash[:notice] = "The #{this_user} avatar has changed."
    else
      flash[:error] = "Avatar not found."
    end
    redirect_to :back
  end

  def destroy
    if avatar = this_user.avatars.find_by_id(params[:id])
      avatar.destroy
      flash[:notice] = "Avatar deleted."
    else
      flash[:error] = "Avatar not found."
    end
    redirect_to :back
  end

end
