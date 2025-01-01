# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesPerUserStartTrackerTest < GitHub::TestCase
  setup_once do
    enable_cache_storage
  end

  teardown_once do
    disable_cache_storage
  end

  setup do
    reset_cache
    @user = create(:user)
    @start_tracker = Codespaces::PerUserStartTracker.new(@user)
    @codespace = create(:codespace)
  end

  context "#track_start" do
    test "adds key to the cache with codespace guid when empty" do
      refute Codespaces::Kv.store.get(@start_tracker.send(:cache_key)).value { nil }
      @start_tracker.track_start(@codespace)
      assert_equal Codespaces::Kv.store.get(@start_tracker.send(:cache_key)).value { nil }, @codespace.guid
    end

    test "replaces existing codespace GUID" do
      @start_tracker.track_start(@codespace)
      assert_equal Codespaces::Kv.store.get(@start_tracker.send(:cache_key)).value { nil }, @codespace.guid

      other_codespace = create(:codespace)
      @start_tracker.track_start(other_codespace)
      assert_equal Codespaces::Kv.store.get(@start_tracker.send(:cache_key)).value { nil }, other_codespace.guid
    end
  end

  context "#codespace_most_recently_started?" do
    test "returns true if codespace is the most recently started" do
      @start_tracker.track_start(@codespace)
      assert @start_tracker.codespace_most_recently_started?(@codespace)
    end

    test "returns false if different codespace was more recently started" do
      other_codespace = create(:codespace)

      @start_tracker.track_start(@codespace)
      refute @start_tracker.codespace_most_recently_started?(other_codespace)
    end

    test "returns false if cache is empty" do
      refute Codespaces::Kv.store.get(@start_tracker.send(:cache_key)).value { nil }
      refute @start_tracker.codespace_most_recently_started?(@codespace)
    end
  end

  context "#codespace_stopped" do
    test "empties cache if codespace matches" do
      @start_tracker.track_start(@codespace)
      @start_tracker.codespace_stopped(@codespace)
      refute Codespaces::Kv.store.get(@start_tracker.send(:cache_key)).value { nil }
    end

    test "doesn't empty cache if codespace doesn't match" do
      @start_tracker.track_start(@codespace)

      other_codespace = create(:codespace)
      @start_tracker.track_start(other_codespace)

      @start_tracker.codespace_stopped(@codespace)
      assert_equal Codespaces::Kv.store.get(@start_tracker.send(:cache_key)).value { nil }, other_codespace.guid
    end

    test "does nothing if cache already empty" do
      refute Codespaces::Kv.store.get(@start_tracker.send(:cache_key)).value { nil }
      @start_tracker.codespace_stopped(@codespace)
      refute Codespaces::Kv.store.get(@start_tracker.send(:cache_key)).value { nil }
    end
  end
end
