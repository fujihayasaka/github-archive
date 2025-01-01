# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class CopilotController < Stafftools::Businesses::BusinessBaseController
      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Billing,
        ApplicationRecord::Collab,
        ApplicationRecord::Copilot,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests,
        only: [:show]

      def show
        organizations = this_business.organizations
        trial_orgs = organization_trials.map(&:trialable)
        active_trials = organization_trials.select(&:active?)
        seat_assignments = []

        if organizations.any?
          seat_assignment_sql = Arel.sql(<<-SQL, organization_ids: this_business.organization_ids)
            SELECT
            cs.organization_id,
            COUNT(*) as seat_count,
            (csa.pending_cancellation_date IS NOT NULL) as pending_cancellation
            FROM copilot_seats cs
            JOIN copilot_seat_assignments csa on csa.id = cs.copilot_seat_assignment_id
            WHERE cs.organization_id IN (:organization_ids)
            GROUP BY organization_id, (csa.pending_cancellation_date IS NULL)
          SQL

          seat_assignments = ::Copilot::SeatAssignment.connection.select_rows(seat_assignment_sql).inject({}) do |memo, result|
            org = organizations.find(result[0])

            memo[result[0]] ||= {
              seat_count: 0,
              seats_pending_cancellation_count: 0,
              organization: org,
              has_trial: trial_orgs.include?(org),
              trial: organization_trials.find { |t| t.trialable == org },
            }
            memo[result[0]][:seat_count] += result[1]
            memo[result[0]][:seats_pending_cancellation_count] += result[2] == 1 ? result[1] : 0
            memo
          end
        end

        copilot_seats = ::Copilot::Seat.joins(:seat_assignment).
                                        where(copilot_seat_assignments: { owner: this_business }).
                                        paginate(page: params[:page] || 1, per_page: 10)

        copilot_seat_emissions = ::Copilot::SeatEmission.for_owner(this_business).order(occurred_at: :desc).paginate(
          page: params[:seat_emissions_page] || 1,
          per_page: 10,
        )

        render "stafftools/businesses/copilot/show", locals: {
          copilot_business: copilot_business,
          seat_assignments: seat_assignments,
          active_trials: active_trials,
          copilot_seats: copilot_seats,
          copilot_seat_emissions: copilot_seat_emissions,
        }
      end

      def generate_csv # rubocop:todo GitHub/UseRestfulActions
        GitHub.dogstats.increment "copilot.stafftools.business.generate_csv"
        GitHub.logger.info("Generating CSV in Business Stafftools", "gh.business.id" => copilot_business.id, "gh.user.id" => current_user.id)
        send_data copilot_business.to_csv, filename: "#{this_business.slug.parameterize}-seat-usage-#{Time.current.to_i}.csv"
      end

      def update_plan # rubocop:todo GitHub/UseRestfulActions
        GitHub.dogstats.increment "copilot.stafftools.business.update_plan"
        GitHub.logger.info("Updating Copilot Plan in Business Stafftools", "gh.business.id" => copilot_business.id, "gh.user.id" => current_user.id, "gh.copilot_plan" => params[:plan])

        if params[:schedule]
          if params[:plan] == "business"
            copilot_business.schedule_copilot_plan_downgrade!(::User.staff_user)
            flash[:info] = "Scheduled downgrade to Copilot Business on #{this_business.next_metered_billing_cycle_starts_at}"
          else
            flash[:error] = "Cannot downgrade to a plan other than Copilot Business"
          end
        elsif params[:plan] == "business"
          business_in_ce_early_access = this_business.feature_enabled?(:copilot_for_enterprise)
          # if there's a pending downgrade date, clear it because we're downgrading immediately
          copilot_business.cancel_copilot_plan_downgrade!
          copilot_business.copilot_for_dotcom_no_policy!(disable_non_trial_orgs_setting: !business_in_ce_early_access)
          copilot_business.copilot_plan_business!
          ::Copilot::Instrumenter.instrument_copilot_plan_changed(::User.staff_user, this_business, "enterprise", "business")

          flash[:info] = "Downgraded business to Copilot Business"
        elsif params[:plan] == "enterprise"
          copilot_business.copilot_plan_enterprise!
          copilot_business.copilot_for_dotcom_enabled!

          CopilotEnterpriseMailer.welcome_business_admins(this_business).deliver_later

          ::Copilot::Instrumenter.instrument_copilot_plan_changed(::User.staff_user, this_business, "business", "enterprise")

          flash[:info] = "Upgraded business to Copilot Enterprise"
        else
          flash[:error] = "Could not update to invalid Copilot plan type"
        end

        redirect_to stafftools_copilot_path(this_business)
      end

      def migrate_to_enterprise_teams # rubocop:todo GitHub/UseRestfulActions
        # The job naming is confusing, but this job works for both EMU and non-EMU enterprises.
        # It will be removed by the end of June so not worth renaming.
        MigrateZeroSKUToBasicEmuJob.perform_later([this_business.slug])

        respond_to do |format|
          format.html_fragment do
            head :ok
          end
          format.html do
            redirect_to stafftools_enterprise_teams_path(this_business)
          end
        end
      end

      def toggle_email_notifications # rubocop:todo GitHub/UseRestfulActions
        if this_business.feature_enabled?(:copilot_communication_opt_out)
          this_business.disable_feature(:copilot_communication_opt_out)
        else
          this_business.enable_feature(:copilot_communication_opt_out)
        end

        result = this_business.feature_enabled?(:copilot_communication_opt_out) ? "disabled" : "enabled"

        GitHub.logger.info(
          "Copilot email notifications #{result} via stafftools",
          "gh.biz.slug" => this_business.slug,
          "gh.actor.login" => current_user,
        )

        flash[:notice] = "Copilot email notifications have been #{result} for #{this_business.slug}"
        redirect_to stafftools_copilot_path(this_business)
      end

      private

      memoize def copilot_business
        ::Copilot::Business.new(this_business)
      end

      memoize def organization_trials
        copilot_business.organization_trials
      end
    end
  end
end
