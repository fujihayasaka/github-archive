# typed: true
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::CodeScanning::AlertDismissalController < AbstractRepositoryController

  def create
    redirect_to :back
  end

  def approve_request # rubocop:todo GitHub/UseRestfulActions
    redirect_to :back
  end

  def reject_request # rubocop:todo GitHub/UseRestfulActions
    redirect_to :back
  end
end
