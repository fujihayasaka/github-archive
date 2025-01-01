# typed: true
# frozen_string_literal: true

# This component exists primarily to make testing the markup
# for the list easy. The list of linked branches is rendered
# in the issue page sidebar.
class Branch::LinkedBranchListComponent < ApplicationComponent
  attr_reader :linked_branches

  def initialize(linked_branches:)
    @linked_branches = linked_branches
  end
end
