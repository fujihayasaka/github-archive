# frozen_string_literal: true

module ProgressBarHelpers
  def assert_progress_bar(total:, opened: 0, closed: 0, skipped: 0)
    done = opened + closed + skipped

    assert_select "[data-test-selector=progress-text]", count: 1, text: /#{done}\s+of\s+#{total}/

    assert_select "[data-test-selector=progress-bar]", count: 1 do
      if opened > 0
        assert_select "[data-test-selector=progress-bar-opened]", count: 1 do |(opened_bar)|
          assert_equal "#{opened} opened", opened_bar["title"]
          assert_match "#{opened * 100 / total}%", opened_bar["style"]
        end
      else
        assert_select "[data-test-selector=progress-bar-opened]", false
      end

      if closed > 0
        assert_select "[data-test-selector=progress-bar-closed]", count: 1 do |(closed_bar)|
          assert_equal "#{closed} closed", closed_bar["title"]
          assert_match "#{closed * 100 / total}%", closed_bar["style"]
        end
      else
        assert_select "[data-test-selector=progress-bar-closed]", false
      end

      if skipped > 0
        assert_select "[data-test-selector=progress-bar-skipped]", count: 1 do |(skipped_bar)|
          assert_equal "#{skipped} skipped", skipped_bar["title"]
          assert_match "#{skipped * 100 / total}%", skipped_bar["style"]
        end
      else
        assert_select "[data-test-selector=progress-bar-skipped]", false
      end
    end
  end

  def refute_progress_bar
    assert_select "[data-test-selector=progress-text]", false
    assert_select "[data-test-selector=progress-bar]", false
  end
end

module ActiveSupport
  class TestCase
    include ProgressBarHelpers
  end
end
