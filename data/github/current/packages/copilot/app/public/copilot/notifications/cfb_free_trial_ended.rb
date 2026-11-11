# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Notifications
    class CfbFreeTrialEnded < NotificationBase
      include GitHub::Memoizer

      def message
        org_for_notification = current_notification_organization
        org_string = org_for_notification ? "the organization #{org_for_notification.display_login}" : "your organization"
        "Your GitHub Copilot Business trial for #{org_string} has ended and was not renewed by your administrators. Contact them for more information."
      end

      def notification_id
        org = current_notification_organization

        return super unless org != nil

        get_notification_id_for_organization(org.organization_object)
      end

      def send_condition
        super do
          current_notification_organization != nil
        end
      end

      private

      memoize def ended_business_trial_orgs
        Copilot::Seat
          .includes(:organization)
          .where(assigned_user_id: copilot_user.id)
          .where.not(organization_id: nil)
          .map { |org| Copilot::Organization.new(T.must(org.organization)) }
          .filter { |copilot_org| copilot_org.business_trial&.expired? }
      end

      def get_notification_id_for_organization(organization)
        "cfb_free_trial_ended_#{organization.id}"
      end

      memoize def current_notification_organization
        # Get notification ids for each org the user has a seat in which have expired trials.
        notification_ids_for_orgs = ended_business_trial_orgs
          .map { |o| get_notification_id_for_organization(o.organization_object) }

        # check for already sent notifications
        sent_ids = Copilot::EditorNotification
          .where(user_id: copilot_user.id)
          .where(notification_id: notification_ids_for_orgs)
          .pluck(:notification_id)

        org_id = notification_ids_for_orgs
          .difference(sent_ids)
          .map { |s| s.split("_").last.to_i }
          .sort
          .first

        return nil unless org_id != nil

        ended_business_trial_orgs.find { |o| o.organization_object.id == org_id }
      end
    end
  end
end
