# typed: true
# frozen_string_literal: true

class MemexSidePanel::Item

  class NotFoundError < StandardError; end
  class PermissionError < StandardError; end
  class InvalidParamsError < StandardError; end
  class UnsupportedError < StandardError; end

  sig { params(this_memex: MemexProject, current_user: T.nilable(User)).void }
  def initialize(this_memex, current_user:)
    @this_memex = this_memex
    @current_user = current_user
  end

  def show(omit_comments:, omit_capabilities:)
    raise UnsupportedError, "show is not implemented"
  end

  def suggestions_target(suggestion_type)
    raise UnsupportedError, "suggestion_target is not implemented"
  end

  def get(*args)
    raise UnsupportedError, "get is not implemented"
  end

  def update(*args)
    raise UnsupportedError, "update is not implemented"
  end

  def comment(*args)
    raise UnsupportedError, "comment is not implemented"
  end

  def edit_comment(*args)
    raise UnsupportedError, "edit_comment is not implemented"
  end

  def update_state(*args)
    raise UnsupportedError, "update_state is not implemented"
  end

  def update_reaction(*args)
    raise UnsupportedError, "update_reaction is not implemented"
  end

  # the below are used by controller to determine item access
  def resource_for_conditional_access(*args)
    raise UnsupportedError, "resource_for_conditional_access is not implemented"
  end

  def target_for_conditional_access(*args)
    raise UnsupportedError, "target_for_conditional_access is not implemented"
  end

  def viewer_can_read?(*args)
    raise UnsupportedError, "viewer_can_read? is not implemented"
  end

  # used to determine if the user can edit the item, but not necessarily the memex
  def viewer_can_update?(*args)
    raise UnsupportedError, "viewer_can_update? is not implemented"
  end

  protected

  sig { returns(MemexProject) }
  attr_reader :this_memex

  sig { returns(T.nilable(User)) }
  attr_reader :current_user
end
