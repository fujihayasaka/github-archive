# typed: true
# frozen_string_literal: true

module SecurityCenter
  class RepositoryLinkComponent < ApplicationComponent
    attr_reader :alert_number, :href, :repository, :show_owner, :system_arguments

    def initialize(alert_number:, href:, repository:, show_owner: false, **system_arguments)
      @alert_number = alert_number
      @href = href
      @repository = repository
      @show_owner = show_owner
      @system_arguments = system_arguments
    end

    memoize def id
      SecureRandom.uuid
    end

    def text
      show_owner ? repository.name_with_display_owner : repository.name
    end
  end
end
