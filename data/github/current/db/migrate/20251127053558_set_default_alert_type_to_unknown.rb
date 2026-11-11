# typed: true
# frozen_string_literal: true

class SetDefaultAlertTypeToUnknown < ActiveRecord::Migration[8.1]
  use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  def change
    change_column_default :security_campaigns, :alert_type, from: 1, to: nil
  end
end
