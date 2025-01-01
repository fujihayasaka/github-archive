# typed: true
# frozen_string_literal: true

class Api::Staff::CodeSecurityTrials < Api::Staff::App
  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  # rubocop:todo GitHub/ControlAccess
  post "/staff/code_security_trial/enterprises/:enterprise", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    enterprise = Business.find_by(slug: params[:enterprise])
    deliver_error! 404 unless enterprise.present?

    data = attr(receive(Hash), :number_of_days_for_trial, :sfdc_poc_url, :reset_private_repos_on_expiration)
    number_of_days = data[:number_of_days_for_trial] || 0
    sfdc_poc_url = data[:sfdc_poc_url] || ""
    reset_private_repos_on_expiration = data[:reset_private_repos_on_expiration] || false
    deliver_error! 400, message: "sfdc_poc_url is required" if sfdc_poc_url.blank?

    trial = make_trial(billable_entity: enterprise)
    begin
      trial.enable(actor: User.ghost, days: number_of_days, api_access: true, sfdc_poc_url:, reset_private_repos_on_expiration:)
    rescue EnterpriseCloudOnboard::SKUTrial::EnablementError => err
      deliver_error! 400, message: err.message
    rescue EnterpriseCloudOnboard::SKUTrial::InvalidNumberOfDays => err
      deliver_error! 400, message: err.message
    end

    deliver_empty status: 201
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  get "/staff/code_security_trial/enterprises/:enterprise", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    enterprise = Business.find_by(slug: params[:enterprise])
    deliver_error! 404 unless enterprise.present?

    # in use?
    trial = make_trial(billable_entity: enterprise)
    is_sku_in_use = trial.feature_is_in_use? || trial.ghas_is_in_use?

    body = {
      is_trial_active: trial.enabled?,
      is_sku_in_use: is_sku_in_use,
      is_in_trial_ready_state: T.let(true, T::Boolean),
      expiry_date: T.let(nil, T.nilable(String)),
      reset_private_repos_on_expiration: T.let(false, T::Boolean),
    }
    errors = trial.enablement_errors(actor: User.ghost, api_access: true)
    if !errors.empty?
      body[:is_in_trial_ready_state] = false
      body[:reason_for_not_in_ready_state] = errors
    end
    if trial.enabled?
      body[:expiry_date] = T.must(trial.expires_at).to_s
      body[:reset_private_repos_on_expiration] = trial.reset_on_expiration?
    end

    deliver_raw body, status: 200
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  delete "/staff/code_security_trial/enterprises/:enterprise", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    enterprise = Business.find_by(slug: params[:enterprise])
    deliver_error! 404 unless enterprise.present?
    trial = make_trial(billable_entity: enterprise)

    if trial.reset_on_expiration?
      StopTrialJob.perform_later(billable_entity: enterprise, sku_name: EnterpriseCloudOnboard::CodeSecurityTrial::SKU_NAME)
      return deliver_empty status: 202
    end

    # stop trial
    trial.disable(actor: User.ghost)

    deliver_empty status: 204
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  patch "/staff/code_security_trial/enterprises/:enterprise", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    enterprise = Business.find_by(slug: params[:enterprise])
    deliver_error! 404 unless enterprise.present?
    trial = make_trial(billable_entity: enterprise)

    # check whether we have a trial
    deliver_error! 400, message: "No Code Security trial" unless trial.enabled?

    # read request body
    data = attr(receive(Hash), :number_of_days_for_trial, :reset_private_repos_on_expiration)
    number_of_days = data[:number_of_days_for_trial]
    reset_private_repos_on_expiration = data[:reset_private_repos_on_expiration]

    # update trial length
    if number_of_days.present?
      begin
        trial.set_number_of_days(actor: User.ghost, days: number_of_days)
      rescue EnterpriseCloudOnboard::SKUTrial::InvalidNumberOfDays => err
        deliver_error! 400, message: err.message
      rescue EnterpriseCloudOnboard::SKUTrial::WouldExpireError => err
        deliver_error! 400, message: err.message
      end
    end

    # update reset on expiration setting
    if !reset_private_repos_on_expiration.nil?
      trial.set_reset_on_expiration(actor: User.ghost, reset_on_expiration: reset_private_repos_on_expiration)
    end

    deliver_empty status: 200
  end
  # rubocop:enable GitHub/ControlAccess


  # rubocop:todo GitHub/ControlAccess
  post "/staff/code_security_trial/organizations/:org", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    org = find_org_by_login
    deliver_error! 404 unless org.present?

    data = attr(receive(Hash), :number_of_days_for_trial, :sfdc_poc_url, :reset_private_repos_on_expiration)
    number_of_days = data[:number_of_days_for_trial] || 0
    sfdc_poc_url = data[:sfdc_poc_url] || ""
    reset_private_repos_on_expiration = data[:reset_private_repos_on_expiration] || false
    deliver_error! 400, message: "sfdc_poc_url is required" if sfdc_poc_url.blank?

    trial = make_trial(billable_entity: org)
    begin
      trial.enable(actor: User.ghost, days: number_of_days, api_access: true, sfdc_poc_url:, reset_private_repos_on_expiration:)
    rescue EnterpriseCloudOnboard::SKUTrial::EnablementError => err
      deliver_error! 400, message: err.message
    rescue EnterpriseCloudOnboard::SKUTrial::InvalidNumberOfDays => err
      deliver_error! 400, message: err.message
    end

    deliver_empty status: 201
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  get "/staff/code_security_trial/organizations/:org", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    org = find_org_by_login
    deliver_error! 404 unless org.present?

    # in use?
    trial = make_trial(billable_entity: org)
    is_sku_in_use = trial.feature_is_in_use? || trial.ghas_is_in_use?

    body = {
      is_trial_active: trial.enabled?,
      is_sku_in_use: is_sku_in_use,
      is_in_trial_ready_state: T.let(true, T::Boolean),
      expiry_date: T.let(nil, T.nilable(String)),
      reset_private_repos_on_expiration: T.let(false, T::Boolean),
    }
    errors = trial.enablement_errors(actor: User.ghost, api_access: true)
    if !errors.empty?
      body[:is_in_trial_ready_state] = false
      body[:reason_for_not_in_ready_state] = errors
    end
    if trial.enabled?
      body[:expiry_date] = T.must(trial.expires_at).to_s
      body[:reset_private_repos_on_expiration] = trial.reset_on_expiration?
    end

    deliver_raw body, status: 200
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  delete "/staff/code_security_trial/organizations/:org", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    org = find_org_by_login
    deliver_error! 404 unless org.present?
    trial = make_trial(billable_entity: org)

    if trial.reset_on_expiration?
      StopTrialJob.perform_later(billable_entity: org, sku_name: EnterpriseCloudOnboard::CodeSecurityTrial::SKU_NAME)
      return deliver_empty status: 202
    end

    # stop trial
    trial.disable(actor: User.ghost)

    deliver_empty status: 204
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  patch "/staff/code_security_trial/organizations/:org", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    org = find_org_by_login
    deliver_error! 404 unless org.present?
    trial = make_trial(billable_entity: org)

    # check whether we have a trial
    deliver_error! 400, message: "No Code Security trial" unless trial.enabled?

    # read request body
    data = attr(receive(Hash), :number_of_days_for_trial, :reset_private_repos_on_expiration)
    number_of_days = data[:number_of_days_for_trial]
    reset_private_repos_on_expiration = data[:reset_private_repos_on_expiration]

    # update trial length
    if number_of_days.present?
      begin
        trial.set_number_of_days(actor: User.ghost, days: number_of_days)
      rescue EnterpriseCloudOnboard::SKUTrial::InvalidNumberOfDays => err
        deliver_error! 400, message: err.message
      rescue EnterpriseCloudOnboard::SKUTrial::WouldExpireError => err
        deliver_error! 400, message: err.message
      end
    end

    # update reset on expiration setting
    if !reset_private_repos_on_expiration.nil?
      trial.set_reset_on_expiration(actor: User.ghost, reset_on_expiration: reset_private_repos_on_expiration)
    end

    deliver_empty status: 200
  end
  # rubocop:enable GitHub/ControlAccess

  private

  sig { params(billable_entity: T.any(Business, Organization)).returns(EnterpriseCloudOnboard::CodeSecurityTrial) }
  def make_trial(billable_entity:)
    ::EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: billable_entity)
  end
end
