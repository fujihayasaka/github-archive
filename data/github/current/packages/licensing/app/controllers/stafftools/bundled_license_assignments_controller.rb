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
      assignments = this_business
        .bundled_license_assignments
        .for_query(params[:query])
        .preload(:user)
        .paginate(page: current_page, per_page: PER_PAGE)
      linked_assignments_count = this_business.assigned_user_bundled_license_assignments_count
      unlinked_assignments_count = this_business.unassigned_user_bundled_license_assignments_count
      matching = %Q[ matching "#{params[:query]}"] if params[:query].present?
      render "stafftools/bundled_license_assignments/enterprise", locals: {
        assignments: assignments,
        header: "Bundled license assignments (#{linked_assignments_count} linked, #{unlinked_assignments_count} unlinked) for #{this_business.name}#{matching}",
        action: "index"
      }
    end

    def perform_user_link_job # rubocop:todo GitHub/UseRestfulActions
      assignment = ::Licensing::BundledLicenseAssignment.find(params[:id])

      if assignment.nil?
        flash[:error] = "Bundled license assignment not found"
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
      matching = %Q[ matching "#{params[:query]}"] if params[:query].present?
      render "stafftools/bundled_license_assignments/orphaned", layout: "stafftools", locals: {
        assignments: assignments,
        header: "Orphaned bundled license assignments#{matching}",
        action: "orphaned"
      }
    end
  end
end
