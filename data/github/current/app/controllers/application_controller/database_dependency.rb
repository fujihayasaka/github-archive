# typed: true
# frozen_string_literal: true

module ApplicationController::DatabaseDependency
  extend T::Helpers
  requires_ancestor { ActionController::Base }

  protected

  def select_write_database
    last_operations = DatabaseSelector::LastOperations.from_session(session)
    ActiveRecord::Base.connected_to(role: :writing) do
      yield
      last_operations.store_latest_writes
    end
  end
end
