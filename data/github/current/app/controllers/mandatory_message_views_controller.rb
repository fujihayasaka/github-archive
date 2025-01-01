# typed: true
# frozen_string_literal: true

class MandatoryMessageViewsController < ApplicationController
  before_action :enterprise_required
  before_action :login_required

  # Skip mandatory_message_check defined in ApplicationController to allow
  # the act of the user viewing/accepting the mandatory message to be registered.
  skip_before_action :mandatory_message_check, only: :create

  def create
    if fully_checked?
      MandatoryMessage.set_user_viewed(current_user)
    else
      flash[:mandatory_message_error] = "Please check all checkboxes to dismiss the message."
    end

    redirect_to :back
  end

  private

  # Safe because of :login_required
  def target_for_conditional_access
    return :no_target_for_conditional_access if anonymous? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def fully_checked?
    boxes = MandatoryMessage.checkbox_count
    return true if boxes == 0

    checked = 0
    params[:checkboxes].each { |_, value| checked += 1 if value == "on" }
    return true if checked == boxes

    false
  end
end
