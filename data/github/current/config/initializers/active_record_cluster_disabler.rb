# typed: true
# frozen_string_literal: true

ActiveSupport.on_load(:active_record) do
  class ActiveRecord::Base
    include GitHub::DatabaseQueryDisabler
  end

  ActiveRecord::ConnectionAdapters::TrilogyAdapter.prepend(GitHub::ConnectionAdapterDisabler)
end
