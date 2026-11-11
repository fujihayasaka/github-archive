# typed: true

class AddMembersRequestSubscribedToBusinessInProductMessagingSubscriptions < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::InProductTargeting)

  def change
    add_column :business_in_product_messaging_subscriptions, :members_request_subscribed, :boolean, null: false, default: true
  end
end
