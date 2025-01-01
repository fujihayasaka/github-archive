# typed: true
# frozen_string_literal: true

module TrackingBlocks
  class RenderContextBlock # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    attr_reader(
      :current_item_display_number,
      :current_owner_login,
      :current_repository_name,
      :current_repository_owner,
      :current_viewer_can_update,
      :current_viewer_write_access
    )

    # current_owner_login: owner canonical login (user or organization login). e.g.: "github"
    #
    # current_repository_name: repository canonical name. e.g.: "primer"
    #
    # current_item_display_number: current item that is embedding the tracking block.
    #                  - for issue, this is the issue number
    #
    # current_viewer_can_update: if the current viewer has write access to the tracking block parent item
    #                            e.g.: user created the issue
    #                 - non logged viewers should always have this set to false

    # current_viewer_write_access: if the current viewer has write access to the repository of
    #                              the tracking block parent item
    #                 - non logged viewers should always have this set to false

    def initialize(
      current_item_display_number: nil,
      current_owner_login:,
      current_repository_name:,
      current_repository_owner: nil,
      current_viewer_can_update: false,
      current_viewer_write_access: false
    )
      @current_item_display_number = current_item_display_number
      @current_owner_login = current_owner_login
      @current_repository_name = current_repository_name
      @current_repository_owner = current_repository_owner
      @current_viewer_can_update = current_viewer_can_update
      @current_viewer_write_access = current_viewer_write_access
    end
  end
end
