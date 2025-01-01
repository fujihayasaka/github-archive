# typed: true
# frozen_string_literal: true

class ActiveRecord::Base
  include GitHub::DatabaseQueryDisabler
end

ActiveRecord::ConnectionAdapters::TrilogyAdapter.prepend(GitHub::ConnectionAdapterDisabler)
