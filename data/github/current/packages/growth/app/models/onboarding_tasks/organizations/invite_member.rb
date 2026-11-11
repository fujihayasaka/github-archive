# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Organizations
    class InviteMember < Base
      # def initialize(organization:, title: "Invite your first member")
      #   @organization = organization
      #   @title = title
      # end

      sig { override.returns(String) }
      def title
        "Invite your first member"
      end

      sig { override.returns(String) }
      def task_link
        org_people_path(organization, enable_tip: true)
      end

      sig { override.returns(String) }
      def icon_path
        "modules/dashboard/suggestions/new-user.svg"
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        begin
          OrganizationInvitation.limit_execution_time.where(organization: organization).exists?
        rescue ActiveRecord::StatementTimeout
          false
        end
      end
    end
  end
end
