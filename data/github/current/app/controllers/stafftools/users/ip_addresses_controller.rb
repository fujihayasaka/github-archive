# typed: true
# frozen_string_literal: true

class Stafftools::Users::IpAddressesController < StafftoolsController
  include Stafftools::Users::ControllerMethods

  layout "stafftools"

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
    only: [:show],
    optional: true

  def show
    users = User.by_ip(params[:id]).not_suspended.order(sort_order).page(current_page)
    index_view = Stafftools::User::IndexView.new(title: "Users at #{params[:id]}")

    render "stafftools/users/index", locals: { view: index_view, users: users }
  end

  private

  def sort_order
    users_sort_labels[user_sort_order] || users_sort_labels[users_sort_labels.keys.first]
  end
end
