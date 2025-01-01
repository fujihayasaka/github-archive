# typed: true
# frozen_string_literal: true

module Stafftools
  class VssSubscriptionEventsController < StafftoolsController
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Ballast,
      ApplicationRecord::Configurations,
      ApplicationRecord::Billing,
      ApplicationRecord::Repositories,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    PER_PAGE = 20

    before_action :ensure_billing_enabled

    def index
      render "stafftools/vss_subscription_events/index", locals: {
        events: ::Licensing::Vss::VssSubscriptionEvent.unsuccessful.paginate(page: current_page, per_page: PER_PAGE)
      }
    end

    def perform # rubocop:todo GitHub/UseRestfulActions
      event = ::Licensing::Vss::VssSubscriptionEvent.find(params[:id])
      ::Licensing::VssSubscriptionEventProcessingJob.perform_now(event)
      flash[:notice] = "Successfully processed event"
    rescue => error # rubocop:todo Lint/GenericRescue
      flash[:error] = error.message
    ensure
      redirect_to stafftools_vss_subscription_events_path
    end

    def investigate # rubocop:todo GitHub/UseRestfulActions
      event = ::Licensing::Vss::VssSubscriptionEvent.find(params[:id])

      if event.update(status: :under_investigation, investigation_notes: params[:investigation_notes])
        flash[:notice] = "Successfully marked event as under investigation"
      else
        flash[:error] = "There was an error marking the event as under investigation (#{event.errors.full_messages.to_sentence})"
      end

      redirect_to stafftools_vss_subscription_events_path
    end
  end
end
