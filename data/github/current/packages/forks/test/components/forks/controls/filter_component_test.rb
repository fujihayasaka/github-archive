# typed: true
# frozen_string_literal: true

require "test_helper"

class Forks::Controls::FilterComponentTest < GitHub::TestCase
  include Forks::SelectMenuTestHelpers
  include Forks::FixtureHelpers

  fixtures do
    @repo = create(:repository, owner: create(:user))
  end

  context "renders" do
    test "it renders with the correct defaults" do
      render_inline(Forks::Controls::FilterComponent.new(path_resolver), allowed_queries: 0)
      assert_selected_option("Active")
      refute_selected_option("Inactive", "Archived", "Starred")
    end

    test "it selects all options indicated by the controls" do
      render_inline(Forks::Controls::FilterComponent.new(
        path_resolver(include: [:starred, :active, :archived])
      ), allowed_queries: 0)

      assert_selected_option("Active", "Starred", "Archived")
      refute_selected_option("Inactive")
    end
  end
end
