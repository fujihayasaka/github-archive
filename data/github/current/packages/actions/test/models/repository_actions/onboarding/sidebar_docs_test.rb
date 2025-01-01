# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryActionsOnboardingSidebarDocsTest < GitHub::TestCase
  if GitHub.enterprise?
    test "does not render the hosted runners section" do
      refute_includes RepositoryActions::Onboarding::SidebarDocs::CONTENT, "Running your jobs on different operating systems"
    end
  else
    test "renders the hosted runners section" do
      assert_includes RepositoryActions::Onboarding::SidebarDocs::CONTENT, "Running your jobs on different operating systems"
    end
  end
end
