# typed: true
# frozen_string_literal: true

module AzureEXP
  autoload :AssignmentClient, "azure_exp/assignment_client"
  autoload :AssignmentResponse, "azure_exp/assignment_response"
  autoload :ExpAssignmentProvider, "azure_exp/exp_assignment_provider"
  autoload :Experiments, "azure_exp/experiments"

  module Experiments
    autoload :Validator, "azure_exp/validator"
  end

  module Beta
    autoload :Namespace, "azure_exp/beta/namespace"
    autoload :Experiment, "azure_exp/beta/experiment"
    autoload :Variant, "azure_exp/beta/variant"
    autoload :ParameterType, "azure_exp/beta/parameter_type"
    autoload :AssignmentState, "azure_exp/beta/assignment_state"
    autoload :Participant, "azure_exp/beta/participant"

    autoload :AssignmentService, "azure_exp/beta/assignment_service"
    autoload :LocalAssignmentService, "azure_exp/beta/local_assignment_service"
    autoload :RemoteAssignmentService, "azure_exp/beta/remote_assignment_service"
    autoload :OverridableExpAssignmentProvider, "azure_exp/beta/overridable_exp_assignment_provider"

    autoload :LocalExperimentationConfig, "azure_exp/beta/local_experimentation_config"

    module LocalExperimentationConfig
      autoload :Config, "azure_exp/beta/local_experimentation_config/config"
      autoload :Namespace, "azure_exp/beta/local_experimentation_config/namespace"
      autoload :Experiment, "azure_exp/beta/local_experimentation_config/experiment"
      autoload :Variant, "azure_exp/beta/local_experimentation_config/variant"
      autoload :ParameterType, "azure_exp/beta/local_experimentation_config/parameter_type"

      autoload :Parser, "azure_exp/beta/local_experimentation_config/parser"

      module Parser
        autoload :ParseError, "azure_exp/beta/local_experimentation_config/parser"
      end
    end

    module RemoteTreatmentAssignment
      autoload :TASResponse, "azure_exp/beta/remote_treatment_assignment/tas_response"
      autoload :Config, "azure_exp/beta/remote_treatment_assignment/config"
    end
  end
end
