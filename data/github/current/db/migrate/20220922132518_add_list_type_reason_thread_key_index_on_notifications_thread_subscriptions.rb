# typed: true

class AddListTypeReasonThreadKeyIndexOnNotificationsThreadSubscriptions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Mysql2)

  def up
    add_index(:notification_thread_subscriptions,
              [:list_type, :reason, :thread_key], length: { thread_key: 11 },
               name: "index_list_type_reason_thread_key_11")
  end

  def down
    remove_index(:notification_thread_subscriptions,
                 name: "index_list_type_reason_thread_key_11")
  end

end
