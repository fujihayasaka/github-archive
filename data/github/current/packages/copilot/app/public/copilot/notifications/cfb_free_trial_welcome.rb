# typed: strict
# frozen_string_literal: true

module Copilot
  module Notifications
    class CfbFreeTrialWelcome < NotificationBase

      include GitHub::Memoizer

      sig { returns(String) }
      def message
        org = current_notification_organization

        return "The admin granted you access to a GitHub Copilot Business trial." unless org != nil

        "The admin of #{org.organization_object.display_login} granted you access to a GitHub Copilot Business trial."
      end

      sig { returns(String) }
      def notification_id
        org = current_notification_organization

        return super unless org != nil

        get_notification_id_for_organization(org.organization_object)
      end

      sig { returns(T::Boolean) }
      def send_condition
        super do
          current_notification_organization != nil
        end
      end

      private

      sig { returns(T::Array[Copilot::Organization]) }
      memoize def active_business_trial_organizations
        Copilot::Seat
        .includes(:organization)
        .where(assigned_user_id: copilot_user.id)
        .where.not(organization_id: nil)
        .map { |s| Copilot::Organization.new(T.must(s.organization)) }
        .filter { |o| o.business_trial&.active? }
        .sort_by { |o| T.must(o.business_trial).started_at }
        .reverse
      end

      sig { params(organization: ::Organization).returns(String) }
      def get_notification_id_for_organization(organization)
        "cfb_free_trial_welcome_#{organization.id}"
      end

      sig { returns(T.nilable(Copilot::Organization)) }
      memoize def current_notification_organization
        # we need to send a notification for every single one of these
        ids_to_send = active_business_trial_organizations
          .map { |o| get_notification_id_for_organization(o.organization_object) }

        # so lets check which we havnt sent yet

        # but first lets pull all the ones we have sent
        sent_ids = Copilot::EditorNotification
          .where(user_id: copilot_user.id)
          .where(notification_id: ids_to_send)
          .pluck(:notification_id)

        # then check which ones we havnt sent yet
        org_id = ids_to_send.difference(sent_ids)
          .first&.split("_")&.last&.to_i

        return nil unless org_id != nil

        active_business_trial_organizations.find { |o| o.organization_object.id == org_id }
      end
    end
  end
end
