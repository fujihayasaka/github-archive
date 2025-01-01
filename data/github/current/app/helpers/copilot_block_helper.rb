# typed: true
# frozen_string_literal: true

# This helper standardizes formatting of the block reason for copilot admin blocks.
# It is used by the copilot settings, copilot bulk block and copilot bulk unblock pages.
module CopilotBlockHelper

  WARN_VIA_SUPPORT = "WARN VIA SUPPORT"
  BAN = "BAN"
  SUPERBAN = "SUPERBAN"
  UNBLOCK = "UNBLOCK"

  def prefix_reason(reason, block_option)
    if block_option == "warn-via-support"
      WARN_VIA_SUPPORT + ": " + reason
    elsif block_option == "ban"
      BAN + ": " + reason
    elsif block_option == "superban"
      SUPERBAN + ": " + reason
    elsif block_option == "unblock"
      UNBLOCK + ": " + reason
    else
      reason
    end
  end

end
