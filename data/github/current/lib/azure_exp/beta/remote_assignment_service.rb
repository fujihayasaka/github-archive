# typed: strict
# frozen_string_literal: true

module AzureEXP::Beta
  class RemoteAssignmentService
    extend T::Sig

    sig { params(participant: Participant).returns(AzureEXP::Beta::RemoteTreatmentAssignment::TASResponse) }
    def self.assignment(participant)
      client = AzureEXP::AssignmentClient.new
      response = client.get_assignment({
        "clientid": participant.randomization_id,
        "ghstaff": participant.staff?,
      }).body

      AzureEXP::Beta::RemoteTreatmentAssignment::TASResponse.new(
        assignment_context: response["AssignmentContext"],
        configs: response["Configs"].map do |config|
          AzureEXP::Beta::RemoteTreatmentAssignment::Config.new(
            id: config["Id"],
            parameters: config["Parameters"],
          )
        end
      )
    end
  end
end
