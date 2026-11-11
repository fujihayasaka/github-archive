# typed: strict
# frozen_string_literal: true

require File.expand_path("query_binder.rb", __dir__)
Dir[File.expand_path("task_locks/*.rb", __dir__)].each { |f| require f }

module ServiceCatalog
  class Client
    # TaskLocksQueryBinder contains methods for accessing task locks.
    class TaskLocksQueryBinder < QueryBinder
    end
  end
end
