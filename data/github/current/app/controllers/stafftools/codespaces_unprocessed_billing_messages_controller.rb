# typed: true
# frozen_string_literal: true

class Stafftools::CodespacesUnprocessedBillingMessagesController < StafftoolsController

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

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  PAGE_SIZE = 30

  before_action :dotcom_required

  def index
    messages = ::Codespaces::UnprocessedBillingMessage.newest_to_oldest.paginate(page: current_page, per_page: PAGE_SIZE)

    render "stafftools/codespaces_unprocessed_billing_messages/index", locals: {
      messages: messages,
    }
  end

  def show
    render "stafftools/codespaces_unprocessed_billing_messages/show", locals: {
      message: ::Codespaces::UnprocessedBillingMessage.find(params[:id])
    }
  end
end
