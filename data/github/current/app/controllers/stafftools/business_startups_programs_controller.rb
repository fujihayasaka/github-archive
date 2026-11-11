# typed: true
# frozen_string_literal: true

module Stafftools
  class BusinessStartupsProgramsController < StafftoolsController
    APPLICATIONS_PAGE_SIZE = 50

    before_action :set_application, only: [:show, :update]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Collab,
      ApplicationRecord::Billing,
      only: [:index, :show, :create, :update]

    CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
      "Stafftools::BusinessStartupsProgramsController#create",
      "Stafftools::BusinessStartupsProgramsController#update"
    ].freeze

    def index
      applications = BusinessStartupsProgram
        .includes(:business)
        .where.not(application_status: nil)
        .order(id: :desc)

      if params[:status].present?
        applications = applications.where(application_status: params[:status])
      end

      paginated_applications = applications.paginate(page: current_page, per_page: APPLICATIONS_PAGE_SIZE)

      render "stafftools/business_startups_programs/index", locals: { applications: paginated_applications }
    end

    def show
      render "stafftools/business_startups_programs/show", locals: {
        application: @application,
      }
    end

    def create
      business = Business.find_by(slug: params[:business_slug].to_s.strip)
      return redirect_to_create_with_error("Business is required.") if business.nil?

      return redirect_to_create_with_error("Business is already enrolled in the startups program.") if business.startups_program

      user = ::User.find_by(login: params[:user_login].to_s.strip)
      return redirect_to_create_with_error("User is required.") if user.nil?
      return redirect_to_create_with_error("User must be the owner of the business.") unless business.owner?(user)

      email = params[:email].to_s.strip
      return redirect_to_create_with_error("Email is required.") if email.blank?
      return redirect_to_create_with_error("Email is not one of the user's verified emails.") unless user.emails.verified.map(&:email).include?(email)

      canonical_partner_id = BusinessStartupsProgram::Partners.canonical(params[:partner_id].to_s.strip)
      return redirect_to_create_with_error("Partner ID is invalid.") if canonical_partner_id.nil?

      form_data = {
        "business_id" => business.id,
        "user_id" => user.id,
        "email" => email,
        "partner_id" => canonical_partner_id,
      }

      startups_program = BusinessStartupsProgram.create!(
        business: business,
        application_status: :processing,
        submitted_at: Time.current,
        payment_card_fingerprint: business.customer&.payment_method&.card_fingerprint,
        payment_azure_subscription_id: business.customer&.azure_subscription_id,
        application_data: form_data
      )

      GlobalInstrumenter.instrument("business_startups_program.submitted", {
        application: startups_program,
        business: business,
        actor: current_user,
      })

      redirect_to T.unsafe(UrlHelpers).stafftools_business_startups_program_path(startups_program),
        notice: "Application submitted."
    end

    def update
      case params[:decision]
      when "screen"
        unless @application.application_status == "pending_review"
          @application.update!(application_status: "pending_review")
        end

        redirect_to T.unsafe(UrlHelpers).stafftools_business_startups_program_path(@application),
          notice: "Application queued for screening."
      when "accept"
        if @application.application_status == "accepted"
          notice = "Application already accepted."
        else
          @application.accept!(actor: current_user)
          notice = acceptance_result_message
          emit_event(:accepted)
        end

        redirect_to T.unsafe(UrlHelpers).stafftools_business_startups_program_path(@application),
          notice: notice
      when "reject"
        if @application.application_status == "rejected"
          flash[:error] = "Application already rejected."
          return redirect_to T.unsafe(UrlHelpers).stafftools_business_startups_program_path(@application)
        end

        reason = params[:reason].to_s.strip
        if reason.blank?
          flash[:error] = "Rejection reason is required."
          return redirect_to T.unsafe(UrlHelpers).stafftools_business_startups_program_path(@application)
        end

        @application.reject!(actor: current_user, rejection_reason: reason)

        emit_event(:rejected)

        redirect_to T.unsafe(UrlHelpers).stafftools_business_startups_program_path(@application),
          notice: "Application rejected."
      else
        redirect_to T.unsafe(UrlHelpers).stafftools_business_startups_program_path(@application),
          alert: "Unknown decision."
      end
    end

    private

    def set_application
      @application = BusinessStartupsProgram.find(params[:id])
    end

    def redirect_to_create_with_error(message)
      flash[:error] = message
      redirect_to T.unsafe(UrlHelpers).stafftools_business_startups_programs_path
    end

    sig { params(decision: Symbol).void }
    def emit_event(decision)
      hydro_payload = {
        application: @application,
        business: @application.business,
        actor: current_user,
      }
      hydro_payload[:rejection_reason] = "stafftools_manual" if decision == :rejected

      GlobalInstrumenter.instrument("business_startups_program.#{decision}", hydro_payload)

      mailer = case decision
      when :accepted then BusinessStartupsApplicationMailer.acceptance_email(@application)
      when :rejected then BusinessStartupsApplicationMailer.rejection_email(@application)
      end
      mailer&.deliver_later

      tags = T.let([], T::Array[String])
      tags << "reason:stafftools_manual" if decision == :rejected

      GitHub.dogstats.increment(
        "business_startups.stafftools.#{decision}",
        tags: tags
      )
    end

    sig { returns(String) }
    def acceptance_result_message
      return "Application accepted." unless params[:apply_credit] == "1"

      credit_result = apply_billing_credit_to_application

      if credit_result[:success]
        "Application accepted and billing credit applied."
      else
        GitHub.logger.error("[GFS] Billing credit failed for application #{@application.id}: #{credit_result[:error_message]}")
        "Application accepted, but billing credit could not be applied. Please try again or apply it manually."
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def apply_billing_credit_to_application
      credit_amount_string = params[:credit_amount].to_s
      amount = ::Billing::Money.parse("$#{credit_amount_string}")

      unless amount.dollars.to_i.between?(1, 10000)
        return { success: false, error_message: "invalid amount" }
      end

      start_date = Time.current
      duration_months = params[:credit_duration_months].to_i.clamp(1, 60)
      end_date = start_date + duration_months.months

      @application.apply_billing_credit(amount: amount, start_date: start_date, end_date: end_date)
    end
  end
end
