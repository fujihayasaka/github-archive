# typed: true
# frozen_string_literal: true

# Finalizes the disablement of a fork Repository in Dependabot by ensuring an install
# has been triggered & checking if there's an existing dependabot config file that
# should be activated.
class Dependabot::RepositoryForkConfigFileDisabledJob < ApplicationJob
  queue_as :dependabot

  retry_on_dirty_exit
  retry_on Dependabot::Twirp::BaseError, wait: :polynomially_longer, attempts: 5

  def self.enqueue(repository:)
    perform_later(repository_id: repository.id)
  end

  def perform(repository_id:)
    repository = Repositories::Public.find_active!(repository_id)

    SecurityProduct::DependabotConfigFile.after_fork_disable(repository: repository)
  end
end
