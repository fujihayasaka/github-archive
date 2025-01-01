# typed: true
# frozen_string_literal: true

class Users::MemexesAssetsController < Users::MemexesController
  include Memexes::SharedMemexesAssetsControllerActions

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Copilot
end
