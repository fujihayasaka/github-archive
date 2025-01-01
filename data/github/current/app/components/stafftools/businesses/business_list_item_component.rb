# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::BusinessListItemComponent < ApplicationComponent
  attr_reader :business, :show_deleted_label, :show_emu_label

  def initialize(business:, show_deleted_label: false, show_emu_label: false)
    @business = business
    @show_deleted_label = show_deleted_label
    @show_emu_label = show_emu_label
  end

  def show_purge_button?
    # the purge button should be hidden for EMU enterprises
    # this is technically an invalid state for an EMU enterprise to be in today; prevent manual purge of existing
    # soft-deleted EMU enterprises
    !(business.enterprise_managed_user_enabled? && !GitHub.flipper[:emu_ea_deletion].enabled?(current_user))
  end
end
