# typed: true
# frozen_string_literal: true

require "test_helper"


module SecurityProductsEnablement::RepositorySettings
  class DependencyGraphAutosubmitMenuItemsComponentTest < GitHub::TestCase
    include GitHub::ComponentTestHelpers

    setup do
      @repo = create(:repository)
    end

    def component(repository, service_enabled: true, labeled_runners_enabled: false, labeled_runners_available: true)
      SecurityProductsEnablement::RepositorySettings::DependencyGraphAutosubmitMenuItemsComponent.new(
        repository:,
        service_enabled:,
        labeled_runners_enabled:,
        labeled_runners_available:,
      )
    end

    test "it renders the options correctly" do
      render_inline component(@repo)

      # The list is correct
      assert_selector(".ActionListItem", count: 3)
      assert_selector(".ActionListItem-label", text: "Enabled")
      assert_selector(".ActionListItem-label", text: "Enabled for labeled runners")
      assert_selector(".ActionListItem-label", text: "Disabled")

      # Nothing is disabled
      refute_selector("[data-test-selector=automatic-dependency-submission-enabled-option] button[aria-disabled=true]")
      refute_selector("[data-test-selector=automatic-dependency-submission-labeled-option] button[aria-disabled=true]")

      # Options have the correct descriptions
      assert_selector("[data-test-selector=automatic-dependency-submission-enabled-option]",
                      text: "Use standard GitHub runners")
      assert_selector("[data-test-selector=automatic-dependency-submission-labeled-option]",
                      text: "Use runners labeled with 'dependency-submission'")
    end

    context "enablement state" do
      test "it renders enabled correctly" do
        render_inline component(@repo)

        assert_selector("[data-test-selector=automatic-dependency-submission-enabled-option] button[aria-checked=true]")
        assert_selector("[data-test-selector=automatic-dependency-submission-labeled-option] button[aria-checked=false]")
        assert_selector("[data-test-selector=automatic-dependency-submission-disabled-option] button[aria-checked=false]")
      end

      test "it renders enabled for labeled runners correctly" do
        render_inline component(@repo, labeled_runners_enabled: true)

        assert_selector("[data-test-selector=automatic-dependency-submission-enabled-option] button[aria-checked=false]")
        assert_selector("[data-test-selector=automatic-dependency-submission-labeled-option] button[aria-checked=true]")
        assert_selector("[data-test-selector=automatic-dependency-submission-disabled-option] button[aria-checked=false]")
      end

      test "it renders disabled correctly" do
        render_inline component(@repo, service_enabled: false)

        assert_selector("[data-test-selector=automatic-dependency-submission-enabled-option] button[aria-checked=false]")
        assert_selector("[data-test-selector=automatic-dependency-submission-labeled-option] button[aria-checked=false]")
        assert_selector("[data-test-selector=automatic-dependency-submission-disabled-option] button[aria-checked=true]")
      end
    end

    test "it disables enable options when Actions is disabled" do
      @repo.disable_actions(actor: @repo.owner)

      render_inline component(@repo)

      assert_selector("[data-test-selector=automatic-dependency-submission-enabled-option] button[aria-disabled=true]",
                      text: "Actions have been disabled")
      assert_selector("[data-test-selector=automatic-dependency-submission-labeled-option] button[aria-disabled=true]",
                      text: "Actions have been disabled")
    end

    test "it disables the labeled runners option when they are not assigned to the repository" do
      render_inline component(@repo, labeled_runners_available: false)

      assert_selector("[data-test-selector=automatic-dependency-submission-labeled-option] button[aria-disabled=true]",
                      text: "No runners with this label assigned to repository")
    end
  end
end
