# frozen_string_literal: true

Rails.configuration.after_initialize do
  DependencyGraph::ActiveRecordRollup.add_rollup_class ActiveRecord::StatementInvalid

  DependencyGraph::ActiveRecordRollup.add_rollup_class ActiveRecord::ConnectionFailed, skip_frame_location: true
  DependencyGraph::ActiveRecordRollup.add_rollup_class ActiveRecord::ConnectionNotEstablished, skip_frame_location: true
  DependencyGraph::ActiveRecordRollup.add_rollup_class ActiveRecord::AdapterTimeout, skip_frame_location: true
end
