# typed: true

class AddMembersRequestSubscribedToOrgInProductMessagingSubscriptions < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::InProductTargeting)

  def change
    add_column :org_in_product_messaging_subscriptions, :members_request_subscribed, :boolean, null: false, default: true
  end
end
