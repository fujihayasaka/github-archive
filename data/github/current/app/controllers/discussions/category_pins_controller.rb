# typed: true
# frozen_string_literal: true

class Discussions::CategoryPinsController < Discussions::BaseController
  include GitHub::Memoizer

  before_action :login_required
  before_action :require_discussion
  before_action :require_category_pin_management
  before_action :require_category_pin, only: [:destroy]
  layout false

  def create
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    pin = DiscussionCategoryPin.new(
      pinned_by: current_user,
      discussion: discussion,
      category: discussion.category
    )

    if pin.save
      flash[:notice] = "Discussion pinned to #{T.must(pin.category).name}"
    else
      flash[:error] = "Could not pin this discussion at this time: " \
      "#{pin.errors.full_messages.to_sentence}"
    end

    redirect_to agnostic_discussion_path(discussion, org_param: org_param)
  end

  def destroy
    if category_pin.destroy
      flash[:notice] = "Discussion unpinned from #{category_pin.category.name}"
    else
      flash[:error] = "Could not unpin this discussion at this time: " \
      "#{category_pin.errors.full_messages.to_sentence}"
    end

    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    redirect_to agnostic_discussion_path(discussion, org_param: org_param)
  end

  private

  memoize def category_pin
    discussion = self.discussion
    return unless discussion
    DiscussionCategoryPin.for_discussion(discussion).first
  end

  def require_category_pin
    render_404 unless category_pin
  end

  def require_category_pin_management
    render_404 unless current_user.can_manage_discussion_category_pins?(current_repository)
  end
end
