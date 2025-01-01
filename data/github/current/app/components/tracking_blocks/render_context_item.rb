# typed: true
# frozen_string_literal: true

module TrackingBlocks
  class RenderContextItem # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    attr_reader :current_owner_login, :current_repository_name, :current_repository_owner
    # current_owner: owner canonical login (user or organization login)
    #
    # current_repository: repository canonical name
    def initialize(current_owner_login: "", current_repository_name: "", current_repository_owner: nil)
      @current_owner_login = current_owner_login
      @current_repository_name = current_repository_name
      @current_repository_owner = current_repository_owner
    end

    def to_issues_href_context
      {
        current_owner: @current_owner_login,
        current_repository: @current_repository_name,
        style_link_normal: true,
        truncate: true,
      }
    end
  end
end
