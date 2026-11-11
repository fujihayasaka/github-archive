# typed: true
# frozen_string_literal: true

class Stafftools::TradeCompliance::TradeScreeningRecordsController < StafftoolsController
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

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    trade_screening_status = params[:sdn_status].presence || "hit_in_review"
    trade_screening_records = ::TradeControls::Filters::TradeScreeningRecordFilter.filter_records \
      current_page: current_page,
      trade_screening_status: trade_screening_status

    respond_to do |format|
      format.html do
        if request.xhr?
          render partial: "stafftools/trade_compliance/trade_screening/listings", locals: {
            trade_screening_records: trade_screening_records,
            trade_screening_status: trade_screening_status,
          }
        else
          render "stafftools/trade_compliance/trade_screening/index", locals: {
            trade_screening_records: trade_screening_records,
            trade_screening_status: trade_screening_status,
          }
        end
      end
    end
  end
end
