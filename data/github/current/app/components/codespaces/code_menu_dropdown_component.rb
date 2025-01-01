# typed: true
# frozen_string_literal: true

module Codespaces
  class CodeMenuDropdownComponent < ApplicationComponent
    include DesktopHelper
    include CodespacesHelper
    include RepositoryAnalyticsHelper
    include RepositoriesHelper
    include StacksHelper

    attr_reader :repository, :pull_request, :ref, :pull_request_context, :visibility
    delegate :has_access_to_codespaces?, to: :visibility

    def initialize(visibility:, repository:, ref:, pull_request: nil)
      @repository = repository
      @pull_request = pull_request
      @ref = ref
      @visibility = visibility
    end
  end
end
