# typed: strict
# frozen_string_literal: true

require "csv"

class Stafftools::TradeCompliance::BatchOperationsController < StafftoolsController
  before_action :authorized_staff_required

  extend T::Sig

  BATCH_SIZE = 1000

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  sig { void }
  def index
    render "stafftools/trade_compliance/index"
  end

  sig { void }
  def create
    return redirect_to stafftools_trade_compliance_batch_operations_path unless valid_reference_number?
    return redirect_to stafftools_trade_compliance_batch_operations_path unless valid_file_selected?
    return redirect_to stafftools_trade_compliance_batch_operations_path unless valid_action_selected?
    return redirect_to stafftools_trade_compliance_batch_operations_path unless valid_test_run_options?

    # Parse the CSV
    # Note: We also pull out any IDs which will need to be revoked
    # e.g. oauth tokens, oauth authorizations, etc...
    begin
      parsed_csv = CSV.parse(File.read(params[:accounts].path), skip_blanks: true, converters: :integer)
      accounts = parsed_csv.map { |row| { id: row[0] } }

      # Parsing the account CSV lead to no accounts
      if accounts.blank?
        flash[:error] = "Parsing of accounts CSV failed, please double check the format."
        return redirect_to stafftools_trade_compliance_batch_operations_path
      end

      # we don't want to run the action on all accounts, but we still want to validate the CSV is correct when
      # it's a test run
      if params[:test_run].to_i == 1
        accounts = [{ id: params[:test_run_account_id].to_i, }]
      end

      batched_ids(accounts).each { |batch| queue_batch_job(batch) }
    rescue CSV::MalformedCSVError => e
      flash[:error] = "Parsing of accounts CSV failed: " + e.message
      return redirect_to stafftools_trade_compliance_batch_operations_path
    end

    if params[:test_run].to_i == 1
      flash[:notice] = "Dry run of incident response job queued for #{params[:reference_number]}!"
    else
      flash[:notice] = "Incident response job queued for #{params[:reference_number]}!"
    end


    instrument("staff.trade_compliance_batch_operation_run", user: current_user, reference_number: params[:reference_number])
    redirect_to stafftools_trade_compliance_batch_operations_path
  end

  private

  sig { void }
  def authorized_staff_required
    render_404 unless current_user.security_incident_response_access?
  end

  sig { returns(T::Boolean) }
  def valid_manual_screening_action?
    # manual screening is always valid because it doesn't require any additional data when checked.
    # This method exists mainly for consistency with the other validation methods
    true
  end

  sig { returns(T::Boolean) }
  def valid_set_screening_status_action?
    return true unless params[:set_screening_status].to_i == 1

    screening_status = params[:screening_status]
    if screening_status.blank?
      flash[:error] = "Set screening status was selected but no screening status was provided!"
      return false
    end

    reason = params[:set_screening_status_reason]
    if reason.blank?
      flash[:error] = "Set screening status was selected but no reason was provided!"
      return false
    end

    true
  end

  sig { returns(T::Boolean) }
  def valid_sdn_suspend_action?
    return true unless params[:sdn_suspend].to_i == 1

    reason = params[:sdn_suspend_reason]
    if reason.blank?
      flash[:error] = "SDN suspend was selected but no reason was provided!"
      return false
    end

    true
  end

  sig { returns(T::Boolean) }
  def valid_sdn_unsuspend_action?
    return true unless params[:sdn_unsuspend].to_i == 1

    reason = params[:sdn_unsuspend_reason]
    if reason.blank?
      flash[:error] = "SDN unsuspend was selected but no reason was provided!"
      return false
    end

    true
  end

  sig { returns(T::Boolean) }
  def valid_file_selected?
    return true unless params[:accounts].blank?

    flash[:error] = "No accounts CSV specified!"
    false
  end

  sig { returns(T::Boolean) }
  def valid_reference_number?
    return true unless params[:reference_number].blank?

    flash[:error] = "No reference number specified!"
    false
  end

  sig { returns(T::Boolean) }
  def valid_action_selected?
    actions = [:manual_screening, :set_screening_status, :sdn_suspend, :sdn_unsuspend]
    actions_selected = actions.select { |action| params[action].to_i == 1 }
    if actions_selected.size != 1
      flash[:error] = if actions_selected.size == 0
        "No action was selected, please select which action you would like to perform"
      else
        "Only one action can be selected at a time!"
      end

      return false
    end

    valid_manual_screening_action? && valid_set_screening_status_action? && valid_sdn_suspend_action? && valid_sdn_unsuspend_action?
  end


  sig { returns(T::Boolean) }
  def valid_test_run_options?
    return true unless params[:test_run].to_i == 1

    account_id = params[:test_run_account_id]
    if account_id.blank?
      flash[:error] = "A test run was selected but no account ID was specified!"
      return false
    end

    if account_id.to_i.to_s != account_id
      flash[:error] = "A test run was selected but the account ID was invalid!"
      return false
    end

    if ::User.find_by(id: account_id).nil?
      flash[:error] = "A test run was selected but the account with ID #{account_id} could not be found!"
      return false
    end

    true
  end

  sig { params(accounts: T::Array[T::Hash[Symbol, Integer]]).returns(T::Enumerator[T::Array[T::Hash[Symbol, Integer]]]) }
  def batched_ids(accounts)
    accounts.each_slice(BATCH_SIZE)
  end

  sig { params(accounts: T::Array[T::Hash[Symbol, Integer]]).void }
  def queue_batch_job(accounts)
    incident_response_account_actions = {
      users: accounts,
    }

    if params[:manual_screening].to_i == 1
      incident_response_account_actions[:sdn_manual_screening] = true
    end

    if params[:set_screening_status].to_i == 1
      incident_response_account_actions[:set_screening_status] = {
        reason: params[:set_screening_status_reason],
        status: params[:screening_status]
      }
    end

    if params[:sdn_suspend].to_i == 1
      incident_response_account_actions[:sdn_suspend] = params[:sdn_suspend_reason]
    end

    if params[:sdn_unsuspend].to_i == 1
      incident_response_account_actions[:sdn_unsuspend] = params[:sdn_unsuspend_reason]
    end

    SecurityIncidentResponseJob.perform_later(
      actor: current_user,
      id: params[:reference_number],
      incident_responses: [
        incident_response_account_actions
      ]
    )
  end
end
