# typed: strict
# frozen_string_literal: true

module Apps
  class KV
    # Source: existing table on lodge (ApplicationRecord::Domain::IntegrationsLodge)
    class LodgeDataStore < ApplicationRecord::Domain::IntegrationsLodge
      self.table_name = "apps_key_values"
    end

    # Target: new table on abilities (ApplicationRecord::Domain::IamAbilities)
    class AbilitiesDataStore < ApplicationRecord::Domain::IamAbilities
      self.table_name = "apps_key_values"
    end
  end
end
