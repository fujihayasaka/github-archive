# typed: false
# frozen_string_literal: true

module Environment::PinDependency
  def pin(actor:)
    return false unless repository.can_pin_environments?(actor)
    return true if repository.pinned_environments.find_by(environment_id: id)
    return false if repository.pinned_environments&.count >= Repository::PinnedEnvironmentsDependency::PINNED_ENVIRONMENTS_LIMIT

    Repository.transaction do
      !!repository.pinned_environments.create!(repository: repository, environment_id: id)
    end
  # Success if a validation or db constraint prevents saving a pinned env which already exists
  rescue ActiveRecord::RecordNotUnique
    true
  rescue ActiveRecord::RecordInvalid => e
    e.message == "Validation failed: Environment has already been taken"
  end

  def unpin(actor:)
    return false unless repository.can_pin_environments?(actor)
    return true if pinned_environment.nil?
    !!pinned_environment.destroy
  end

  def pinned?
    !!pinned_environment
  end
end
