# typed: true
# frozen_string_literal: true

require "test_helper"

class VulnerableVersionRangeAlertingProcessTest < GitHub::TestCase
  context ".not_processed" do
    test "returns records with no processed_at value set" do
      process_1  = create(:vulnerable_version_range_alerting_process, processed_at: nil)
      _process_2 = create(:vulnerable_version_range_alerting_process, processed_at: 2.minutes.ago)
      process_3  = create(:vulnerable_version_range_alerting_process, processed_at: nil)
      _process_4 = create(:vulnerable_version_range_alerting_process, processed_at: 1.minute.ago)

      not_processed = VulnerableVersionRangeAlertingProcess.not_processed
      assert_kind_of ActiveRecord::Relation, not_processed
      assert_equal 2, not_processed.count
      assert_same_elements [process_1, process_3], not_processed
    end
  end

  context "#processing!" do
    test "marks the alerting process as processing" do
      process = create(:vulnerable_version_range_alerting_process, :preprocessing)

      assert_changes -> { process.processing? }, from: false, to: true do
        assert_equal true, process.processing!
      end
    end

    test "sets the alert count to zero" do
      process = create(:vulnerable_version_range_alerting_process, :preprocessing)

      assert_changes -> { process.alert_count }, from: nil, to: 0 do
        process.processing!
      end
    end

    test "extends the active processing expiration time" do
      process = create(:vulnerable_version_range_alerting_process, :preprocessing)
      process.processing!
      active_expiration_1 = process.send(:redis).ttl(process.send(:processing_active_key))

      sleep 1
      active_expiration_2 = process.send(:redis).ttl(process.send(:processing_active_key))

      process.processing!
      active_expiration_3 = process.send(:redis).ttl(process.send(:processing_active_key))

      assert_operator active_expiration_1, :>, active_expiration_2
      assert_operator active_expiration_3, :>, active_expiration_2
    end

    test "doesn't reset the alert count" do
      process = create(:vulnerable_version_range_alerting_process, :preprocessing)

      assert_changes -> { process.alert_count }, from: nil, to: 0 do
        process.processing!
      end

      assert_changes -> { process.alert_count }, from: 0, to: 1 do
        process.increment_alert_count(1)
      end

      assert_no_changes -> { process.alert_count }, from: 1 do
        process.processing!
      end
    end
  end

  context "#processing?" do
    test "returns false if not yet processing" do
      process = create(:vulnerable_version_range_alerting_process, :preprocessing)

      assert_equal false, process.processing?
    end

    test "returns false if already processed" do
      process = create(:vulnerable_version_range_alerting_process, :processed)

      assert_equal false, process.processing?
    end

    test "returns true if processing started recently" do
      process = create(:vulnerable_version_range_alerting_process, :preprocessing)

      assert_changes -> { process.processing? }, from: false, to: true do
        process.processing!
      end
    end
  end

  context "#processing_stalled!" do
    test "does nothing if not yet processing" do
      process = create(:vulnerable_version_range_alerting_process, :preprocessing)

      assert_no_changes -> { process.processing_stalled? }, from: false do
        assert_equal false, process.processing_stalled!
      end
    end

    test "does nothing if already processed" do
      process = create(:vulnerable_version_range_alerting_process, :processed)

      assert_no_changes -> { process.processing_stalled? }, from: false do
        assert_equal false, process.processing_stalled!
      end
    end

    test "marks the alerting process as stalled" do
      process = create(:vulnerable_version_range_alerting_process, :processing)

      assert_changes -> { process.processing_stalled? }, from: false, to: true do
        assert_equal true, process.processing_stalled!
      end
    end

    test "does nothing if already stalled" do
      process = create(:vulnerable_version_range_alerting_process, :processing_stalled)

      assert_no_changes -> { process.processing_stalled? }, from: true do
        assert_equal true, process.processing_stalled!
      end
    end
  end

  context "#processing_stalled?" do
    test "returns false if not yet processing" do
      process = create(:vulnerable_version_range_alerting_process, :preprocessing)

      assert_equal false, process.processing_stalled?
    end

    test "returns false if processing has just begun" do
      process = create(:vulnerable_version_range_alerting_process, :processing)

      assert_equal false, process.processing_stalled?
    end

    test "returns false if processing has finished" do
      process = create(:vulnerable_version_range_alerting_process, :processed)

      assert_equal false, process.processing_stalled?
    end

    test "returns true if no activity was recorded in the first eight hours" do
      process = create(:vulnerable_version_range_alerting_process, :preprocessing)
      process.processing!

      assert_changes -> { process.processing_stalled? }, from: false, to: true do
        # Manually expire the processing-active key.
        process.send(:redis).expire(process.send(:processing_active_key), 0)
      end
    end
  end

  context "#processed!" do
    test "does nothing if already processed" do
      process = create(:vulnerable_version_range_alerting_process, :processed)

      assert_no_changes -> { process.reload.attributes } do
        assert_equal false, process.processed!
      end

      refute process.processing?
      assert process.processed?
    end

    test "touches the processed_at column" do
      now = Time.current.round
      Timecop.freeze(now) do
        process = create(:vulnerable_version_range_alerting_process, :processing)

        assert_changes -> { process.reload.processed_at }, from: nil, to: now do
          process.processed!
        end

        refute process.processing?
        assert process.processed?
      end
    end

    test "updates its parent event if its siblings are all processed" do
      event = create(:vulnerability_alerting_event, :on_process_alerts, :unprocessed)
      process = create(:vulnerable_version_range_alerting_process, :processing, vulnerability_alerting_event: event)
      create(:vulnerable_version_range_alerting_process, :processed, vulnerability_alerting_event: event)

      assert_changes -> { event.reload.processed? }, from: false, to: true do
        process.processed!
      end
    end

    test "doesn't update its parent if its siblings aren't all processed" do
      event = create(:vulnerability_alerting_event, :on_process_alerts, :unprocessed)
      process = create(:vulnerable_version_range_alerting_process, :processing, vulnerability_alerting_event: event)
      create(:vulnerable_version_range_alerting_process, :processing, vulnerability_alerting_event: event)

      assert_no_changes -> { event.reload.processed? } do
        process.processed!
      end
    end

    test "#increment_alert_count" do
      process = create(:vulnerable_version_range_alerting_process, :processing, alert_count: 0)

      assert_changes -> { process.alert_count }, from: 0, to: 1 do
        process.increment_alert_count(1)
      end

      assert_changes -> { process.alert_count }, from: 1, to: 3 do
        process.increment_alert_count(2)
      end
    end
  end
end
