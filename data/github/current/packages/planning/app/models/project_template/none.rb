# typed: true
# frozen_string_literal: true

# Provides information for the UI to create project templates.
#
# See ProjectTemplate for usage instructions :sparkles:
#
class ProjectTemplate::None < ProjectTemplate
  def build; end

  def self.title
    "None"
  end

  # -----------------------------------------------
  # Meta information about this template for the UI
  #
  def self.description
    "Start from scratch with a completely blank project board. You can add columns and configure automation settings yourself."
  end
end
