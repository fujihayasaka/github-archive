# typed: strict
# frozen_string_literal: true
#
# This module encapsulates most used workflow queries for workflow runners and jobs
module MemexProjectWorkflow::WorkflowQueries
  extend T::Sig

  sig { params(id: Integer).returns(T.nilable(MemexProjectItem)) }
  private def project_item(id)
    with_read do
      MemexProjectItem.find_by(id: id)
    end
  end

  # Simple wrapper for connecting to read pool for read operations only.
  sig do
    # This method has a generic return type which is defined by the return type of whatever block is passed in.
    type_parameters(:BlockReturn)
      .params(blk: T.proc.returns(T.type_parameter(:BlockReturn)))
      .returns(T.type_parameter(:BlockReturn))
  end
  private def with_read(&blk)
    ActiveRecord::Base.connected_to(role: :reading) do
      yield
    end
  end

  # Simple wrapper for connecting to write pool for write operations only.
  sig do
    # This method has a generic return type which is defined by the return type of whatever block is passed in.
    type_parameters(:BlockReturn)
      .params(blk: T.proc.returns(T.type_parameter(:BlockReturn)))
      .returns(T.type_parameter(:BlockReturn))
  end
  private def with_write_values(&blk)
    ActiveRecord::Base.connected_to(role: :writing) do
      MemexProjectColumnValue.throttle do
        yield
      end
    end
  end
end
