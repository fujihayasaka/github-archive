# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::BusinessListItemComponent < ApplicationComponent
  attr_reader :business, :show_deleted_label, :show_emu_label

  def initialize(business:, show_deleted_label: false, show_emu_label: false)
    @business = business
    @show_deleted_label = show_deleted_label
    @show_emu_label = show_emu_label
  end

  def can_purge_or_restore?
    # We can't purge or restore if DestroyBusinessJob is currently running.
    !DestroyBusinessJob.status(business.id)&.state&.in? %[pending queued started]
  end
end
