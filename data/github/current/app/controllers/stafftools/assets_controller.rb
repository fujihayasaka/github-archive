# typed: false
# frozen_string_literal: true

class Stafftools::AssetsController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    only: [:avatar]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show], optional: true

  def index
    oid = params[:oid]

    if oid.blank?
      render "stafftools/assets/index"
    else
      redirect_to stafftools_asset_path(oid)
    end
  end

  def show
    oid = params[:oid]
    @asset = oid.present? && Asset.find_by_oid(oid)
    if @asset
      render "stafftools/assets/show"
    else
      redirect_to stafftools_assets_path
    end
  end

  def avatar # rubocop:todo GitHub/UseRestfulActions
    id = params[:id].to_i
    if @avatar = id > 0 && Avatar.find_by_id(id)
      redirect_to stafftools_user_avatars_path(@avatar.owner, avatar_id: id.to_i)
    else
      redirect_to stafftools_assets_path
    end
  end
end
