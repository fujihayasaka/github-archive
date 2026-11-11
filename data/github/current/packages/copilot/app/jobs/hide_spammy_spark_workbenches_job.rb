# typed: true
# frozen_string_literal: true

class HideSpammySparkWorkbenchesJob < ApplicationJob
  queue_as :hide_spammy_spark_workbenches

  retry_on_dirty_exit

  sig { params(user_id: Integer).void }
  def perform(user_id)
    return unless user = User.find_by(id: user_id)
    return unless user.spammy?
    return unless user.feature_flag_enabled_or_raise?(:hide_spammy_spark_workbenches) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    Spark::Workbench.where(user_id: user_id).find_each do |spark|
      Spark::Workbench.throttle do
        with_write { spark.hide }
      end
    end
  end
end
