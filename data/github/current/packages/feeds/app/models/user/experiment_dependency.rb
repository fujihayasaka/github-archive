# typed: false
# frozen_string_literal: true

module User::ExperimentDependency
  include AzureEXP::Experiments

  def assigned?(experiment, variant: nil)
    @assigned ||= Hash.new do |memo, (experiment, variant)|
      memo[[experiment, variant]] = Assignments.new.assigned?(self, experiment, variant: variant)
    end

    @assigned[[experiment, variant]]
  end
end
