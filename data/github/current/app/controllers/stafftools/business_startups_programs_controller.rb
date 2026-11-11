# typed: true
# frozen_string_literal: true

module Stafftools
  class BusinessStartupsProgramsController < StafftoolsController
    APPLICATIONS_PAGE_SIZE = 50

    before_action :ensure_gfs_new_form_enabled
    before_action :set_application, only: [:show, :update]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Collab,
      ApplicationRecord::Billing,
      only: [:index, :show, :update]

    CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
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

    def update
      case params[:decision]
      when "screen"
        @application.update!(application_status: "pending_review")

        redirect_to T.unsafe(UrlHelpers).stafftools_business_startups_program_path(@application),
          notice: "Application queued for screening."
      when "accept"
        @application.accept!(actor: current_user)
        notice = acceptance_result_message

        emit_event(:accepted)

        redirect_to T.unsafe(UrlHelpers).stafftools_business_startups_program_path(@application),
          notice: notice
      when "reject"
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

    def ensure_gfs_new_form_enabled
      render_404 unless FeatureFlag.vexi.enabled?(:gfs_new_form, current_user, default: false)
    end

    def set_application
      @application = BusinessStartupsProgram.find(params[:id])
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

      if FeatureFlag.vexi.enabled?(:gfs_new_mailer, default: false)
        mailer = case decision
        when :accepted then BusinessStartupsApplicationMailer.acceptance_email(@application)
        when :rejected then BusinessStartupsApplicationMailer.rejection_email(@application)
        end
        mailer&.deliver_later
      end

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
