# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

class StacksInstanceQuery

  # Given repository ids
  # returns stack instances which have not started status
  def self.not_started_stacks_instances(repository_ids)
    StacksInstance.includes(:instance_repository).where(instance_repository_id: repository_ids)
                          .select { |instance| instance.not_started? }
  end
end
