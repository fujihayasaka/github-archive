# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::OrchestrationsComponent < ApplicationComponent
  def initialize(title, repository_orchestrations)
    @title = title
    @repository_orchestrations = repository_orchestrations
  end
end
