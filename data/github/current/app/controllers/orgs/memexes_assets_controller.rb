# typed: true
# frozen_string_literal: true

class Orgs::MemexesAssetsController < Orgs::MemexesController
  include Memexes::SharedMemexesAssetsControllerActions

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot
end
