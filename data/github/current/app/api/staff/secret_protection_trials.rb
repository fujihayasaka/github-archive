# typed: true
# frozen_string_literal: true

class Api::Staff::SecretProtectionTrials < Api::Staff::App
  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  # rubocop:todo GitHub/ControlAccess
  post "/staff/secret_protection_trial/enterprises/:enterprise_id", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    enterprise = T.let(find_enterprise!, Business)

    data = attr(receive(Hash), :number_of_days_for_trial)
    number_of_days = data[:number_of_days_for_trial]

    trial = make_trial(billable_entity: enterprise)
    begin
      trial.enable(actor: User.ghost, days: number_of_days)
    rescue EnterpriseCloudOnboard::SKUTrial::EnablementError => err
      deliver_error! 400, message: err.message
    rescue EnterpriseCloudOnboard::SKUTrial::InvalidNumberOfDays => err
      deliver_error! 400, message: err.message
    end

    deliver_empty status: 201
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  get "/staff/secret_protection_trial/enterprises/:enterprise_id", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    enterprise = T.let(find_enterprise!, Business)

    # in use?
    trial = make_trial(billable_entity: enterprise)
    is_sku_in_use = trial.feature_is_in_use? || trial.ghas_is_in_use?

    body = {
      is_trial_active: trial.enabled?,
      is_sku_in_use: is_sku_in_use,
      is_in_trial_ready_state: T.let(true, T::Boolean),
      expiry_date: T.let(nil, T.nilable(String)),
    }
    errors = trial.enablement_errors(actor: User.ghost)
    if !errors.empty?
      body[:is_in_trial_ready_state] = false
      body[:reason_for_not_in_ready_state] = errors
    end
    if trial.enabled?
      body[:expiry_date] = T.must(trial.expires_at).to_s
    end

    deliver_raw body, status: 200
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  patch "/staff/secret_protection_trial/enterprises/:enterprise_id", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    enterprise = T.let(find_enterprise!, Business)
    trial = make_trial(billable_entity: enterprise)

    # check whether we have a trial
    deliver_error! 400, message: "No Secret Protection trial" unless trial.enabled?

    # read request body
    data = attr(receive(Hash), :number_of_days_for_trial)
    number_of_days = data[:number_of_days_for_trial]

    # update trial length
    begin
      trial.set_number_of_days(actor: User.ghost, days: number_of_days)
    rescue EnterpriseCloudOnboard::SKUTrial::InvalidNumberOfDays => err
      deliver_error! 400, message: err.message
    rescue EnterpriseCloudOnboard::SKUTrial::WouldExpireError => err
      deliver_error! 400, message: err.message
    end

    deliver_empty status: 200
  end
  # rubocop:enable GitHub/ControlAccess

  sig { params(billable_entity: Business).returns(EnterpriseCloudOnboard::SecretProtectionTrial) }
  def make_trial(billable_entity:)
    EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: billable_entity, api_access: true)
  end
end
