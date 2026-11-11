# typed: true
# frozen_string_literal: true

module Stafftools
  class BundledLicenseAssignmentsController < Stafftools::Businesses::BusinessBaseController
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Ballast,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Billing,
      ApplicationRecord::Mysql5,
      only: [:index]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Ballast,
      ApplicationRecord::Configurations,
      ApplicationRecord::Billing,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      only: [:orphaned]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index, :orphaned], optional: true

    PER_PAGE = 20

    skip_before_action :business_required, only: :orphaned

    def index
      assignments = this_business.bundled_license_assignments
      assignments = assignments.for_enterprise_agreement(params[:agreement_id]) if params[:agreement_id].present?
      assignments = assignments
        .for_query(params[:query])
        .preload(:user)
        .paginate(page: current_page, per_page: PER_PAGE)

      count_base = this_business.bundled_license_assignments
      count_base = count_base.for_enterprise_agreement(params[:agreement_id]) if params[:agreement_id].present?
      linked_assignments_count = count_base.assigned_user.count
      unlinked_assignments_count = count_base.unassigned_user.count

      render "stafftools/bundled_license_assignments/enterprise", locals: {
        assignments: assignments,
        linked_count: linked_assignments_count,
        unlinked_count: unlinked_assignments_count,
        agreement_id: params[:agreement_id],
        query: params[:query],
        action: "index"
      }
    end

    def perform_user_link_job # rubocop:todo GitHub/UseRestfulActions
      assignment = ::Licensing::BundledLicenseAssignment.find(params[:id])

      if assignment.nil?
        flash[:error] = "Assignment not found"
      else
        assignment.attempt_to_assign_user_from_business
        flash[:notice] = "SetUserFromBusinessOnBundledLicenseAssignmentJob enqueued"
      end

      redirect_to :back
    end

    def orphaned # rubocop:todo GitHub/UseRestfulActions
      assignments = ::Licensing::BundledLicenseAssignment
        .unassigned_business
        .nonrevoked
        .for_query(params[:query])
        .preload(:user)
        .paginate(page: current_page, per_page: PER_PAGE)

      render "stafftools/bundled_license_assignments/orphaned", layout: "stafftools", locals: {
        assignments: assignments,
        query: params[:query],
        action: "orphaned"
      }
    end
  end
end
