# typed: true
# frozen_string_literal: true

Rails.configuration.after_initialize do
  GitHub::Exceptions::BasicRollup.rollup_classes << ::Aqueduct::Worker::JobKilled

  GitHub::Exceptions::ActiveRecordRollup.add_rollup_class ActiveRecord::StatementInvalid

  GitHub::Exceptions::ActiveRecordRollup.add_rollup_class ActiveRecord::ConnectionFailed, skip_frame_location: true
  GitHub::Exceptions::ActiveRecordRollup.add_rollup_class ActiveRecord::ConnectionNotEstablished, skip_frame_location: true
  GitHub::Exceptions::ActiveRecordRollup.add_rollup_class ActiveRecord::AdapterTimeout, skip_frame_location: true
end
