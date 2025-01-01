# typed: true
# frozen_string_literal: true

class Api::Staff::CodeSecurityTrials < Api::Staff::App
  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  # rubocop:todo GitHub/ControlAccess
  post "/staff/code_security_trial/enterprises/:enterprise_id", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
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

  private

  sig { params(billable_entity: Business).returns(EnterpriseCloudOnboard::CodeSecurityTrial) }
  def make_trial(billable_entity:)
    ::EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: billable_entity, api_access: true)
  end
end
