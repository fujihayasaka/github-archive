# typed: strict
# frozen_string_literal: true

class Stafftools::CopilotBusinessTrialsController < StafftoolsController
  layout "layouts/stafftools/user/content"

  before_action :dotcom_required

  sig { void }
  def create
    redirect_to stafftools_user_copilot_settings_path(this_user) and return unless this_user.organization?

    duration = params.fetch(:duration, 30).to_i
    copilot_plan = params.fetch(:copilot_plan, "business")

    copilot_org = Copilot::Organization.new(this_user)
    business_trial = copilot_org.business_trial

    if business_trial.present?
      flash[:error] = "#{business_trial.display_name} already exists for this organization."
    elsif copilot_org.spammy?
      flash[:error] = "Copilot #{copilot_plan.capitalize} Trial cannot be created for this organization."
    elsif copilot_plan == "enterprise" && this_user.business.nil?
      # Standalone orgs aren't eligible for Copilot Enterprise trials
      flash[:error] = "Copilot Enterprise Trial can only be created for an organization that is part of an enterprise."
    elsif copilot_plan == "enterprise" && this_user.business&.digital_front_door?
      flash[:error] = "Copilot Enterprise Trial cannot be created when business is a part of Digital Front Door."
    else
      begin
        Copilot::BusinessTrial.create_trial!(
          this_user,
          current_user,
          trial_length: duration,
          copilot_plan: copilot_plan,
        )

        # we need to make sure that if there's a business, its enablement setting is set to "selected organizations"
        # passing an empty array means we won't actually enable copilot for this organization yet
        # (and won't send a confusing email in addition to the welcome email). This also does not instrument the
        # COPILOT_FOR_BUSINESS_ENTERPRISE_ORG_ENABLEMENT_CHANGED event.
        if copilot_org.copilot_business
          T.must(copilot_org.copilot_business).enable_copilot_for_selected_organizations!([])

          # Set the CE policy to "No policy" if not enabled already upon Copilot Enterprise trial creation
          if copilot_plan == "enterprise" && !copilot_org.copilot_business&.copilot_for_dotcom_enabled?
            T.must(copilot_org.copilot_business).copilot_for_dotcom_no_policy!
          end
        end

        # we also want to make sure copilot is enabled for the org this trial was created for
        copilot_org.enable_copilot!

        # seat_count is no longer relevant when creating a trial, but it is still a required field
        Copilot::Instrumenter.instrument_copilot_business_trial_created(current_user, this_user, 0, duration, copilot_plan)

        flash[:notice] = "Copilot #{copilot_plan.capitalize} Trial created for this organization."
      rescue ActiveRecord::ActiveRecordError => e
        GitHub.logger.info(
          "Copilot trial could not be created",
          "gh.copilot.business_trial.copilot_plan" => copilot_plan,
          "gh.organization.id" => this_user.id,
          "gh.error.message" => e.message,
        )

        flash[:error] = "Copilot #{copilot_plan.capitalize} Trial #{e.message}"
      end
    end

    redirect_to stafftools_user_copilot_settings_path(this_user)
  end

  sig { void }
  def destroy
    if this_user.organization?
      copilot_organization = Copilot::Organization.new(this_user)
      business_trial = copilot_organization.business_trial

      if business_trial.present?
        business_trial.cancel!
        if business_trial.copilot_plan_business?
          if this_user.business.present?
            Copilot::Business.new(this_user.business).disable_copilot_for_selected_organizations!([this_user.id])
          else
            copilot_organization.disable_copilot! unless business_trial.trialable_is_copilot_billable?
            copilot_organization.seat_management_disable!
          end
        elsif business_trial.copilot_plan_enterprise?
          business_trial.process_disabling_copilot_enterprise_features
        end

        Copilot::Instrumenter.instrument_copilot_business_trial_changed(
          current_user,
          business_trial,
          "Trial canceled",
          business_trial.ends_at,
          business_trial.copilot_plan,
        )
        flash[:notice] = "Copilot #{business_trial.copilot_plan.capitalize} Trial canceled for this organization."
      else
        flash[:error] = "Copilot Business/Enterprise Trial does not exist for this organization."
      end
    else
      flash[:error] = "Copilot Business/Enterprise Trial can only be canceled for organizations."
    end

    redirect_to stafftools_user_copilot_settings_path(this_user)
  end

  sig { void }
  def update
    if this_user.organization?
      copilot_organization = Copilot::Organization.new(this_user)
      business_trial = copilot_organization.business_trial

      if business_trial.present?
        if params[:duration].present?
          duration = params.fetch(:duration, 30).to_i

          if params[:copilot_plan].present?
            copilot_plan = params.fetch(:copilot_plan, "enterprise")
            if this_user.business&.digital_front_door?
              flash[:error] = "Copilot Enterprise Trial cannot be updated when business is a part of Digital Front Door."
            else
              update_plan(business_trial, copilot_organization, copilot_plan, duration)
            end
          else
            business_trial.extend_trial!(current_user, duration)

            flash[:notice] = "#{business_trial.display_name} extended for this organization."
          end
        elsif params[:restart].present?
          business_trial.restart!
          flash[:notice] = "#{business_trial.display_name} restarted for this organization."
        else
          begin
            business_trial.upgrade!(current_user)
            if params[:upgrade_only] == "true"
              flash[:notice] = "#{business_trial.display_name} upgraded for this organization."
              redirect_to stafftools_user_copilot_settings_path(this_user) and return
            end

            if this_user.business.present? && copilot_biz = Copilot::Business.new(this_user.business)
              GitHub.logger.with_named_tags(
                "gh.copilot.business_trial.id" => business_trial.id,
                "gh.organization.id" => this_user.id,
                "gh.business.id" => this_user.business.id,
              ) do
                if business_trial.copilot_plan_business?
                  GitHub.logger.info("Enabling Copilot for selected orgs with Copilot Business trial upgrade")
                  copilot_biz.enable_copilot_for_selected_organizations!([this_user.id])
                  copilot_organization.copilot_plan_business!
                elsif business_trial.copilot_plan_enterprise?
                  GitHub.logger.info("Enabling Copilot Enterprise with Copilot Enterprise trial upgrade")

                  copilot_organization.copilot_plan_enterprise!
                  copilot_biz.copilot_plan_enterprise!
                  copilot_biz.copilot_for_dotcom_enabled!

                  ::Copilot::Instrumenter.instrument_copilot_plan_changed(::User.staff_user, this_user, "business", "enterprise")
                end
              end
            end

            flash[:notice] = "#{business_trial.display_name} upgraded for this organization."
          rescue Copilot::Errors::OrgTrialUpgradeError
            GitHub.logger.info(
              "Copilot trial is not upgradable",
              "gh.copilot.business_trial.id" => business_trial.id,
              "gh.organization.id" => this_user.id,
            )

            flash[:error] = "#{business_trial.display_name} could not be upgraded for this organization."
          end
        end
      else
        flash[:error] = "Copilot Business/Enterprise Trial does not exist for this organization."
      end
    else
      flash[:error] = "Copilot Business/Enterprise Trial can only be updated for organizations."
    end

    redirect_to stafftools_user_copilot_settings_path(this_user)
  end

  private

  sig do
    params(
      business_trial: Copilot::BusinessTrial,
      copilot_org: Copilot::Organization,
      copilot_plan: String,
      duration: Integer
    ).void
  end
  def update_plan(business_trial, copilot_org, copilot_plan, duration)
    if copilot_plan == "business"
      flash[:error] = "Only conversion to Copilot Enterprise trial is supported at this time."
    elsif this_user.business.nil?
      flash[:error] = "Copilot Enterprise Trial can only be for an organization that is part of an enterprise."
    elsif business_trial.trialable_business_already_on_copilot_enterprise?
      flash[:error] = "This organization's enterprise is already on Copilot Enterprise."
    elsif this_user.business.present? && existing_trial_has_different_plan?(copilot_plan)
      flash[:error] = "Copilot Trial must be of the same type as existing organization trials in the enterprise."
    elsif !business_trial.trialable_is_copilot_billable?
      flash[:error] = "This organization is not billable for GitHub Copilot."
    else
      business_trial.convert_trial!(current_user, new_trial_length: duration, new_copilot_plan: copilot_plan)

      flash[:notice] = "Copilot Trial successfully converted to #{copilot_plan.capitalize}."
    end
  end

  sig { params(desired_copilot_plan: String).returns(T::Boolean) }
  def existing_trial_has_different_plan?(desired_copilot_plan)
    Copilot::BusinessTrial.existing_trial_in_org_has_different_plan?(this_user, desired_copilot_plan)
  end
end
