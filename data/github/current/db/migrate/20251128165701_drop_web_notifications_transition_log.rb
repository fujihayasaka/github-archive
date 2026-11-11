# typed: true
# frozen_string_literal: true

class DropWebNotificationsTransitionLog < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    drop_table :web_notifications_transition_log, if_exists: true
  end
end
