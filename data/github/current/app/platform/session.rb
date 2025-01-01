# typed: true
# frozen_string_literal: true

module Platform
  module Session
    extend T::Sig

    sig { params(query: GraphQL::Query, context: Platform::IContext).returns(GraphQL::Query::Result) }
    def self.run(query, context)
      last_operations = setup_last_operations(context)

      set_database_role(last_operations, query, context) do
        query.result
      end
    ensure
      if query.mutation? && !readonly_forced?(context)
        last_operations.store_latest_writes
      end
    end

    def self.set_database_role(last_operations, query, context, &blk)
      DatabaseSelector.instance.track_writes(last_operations) do
        if readonly_forced?(context)
          set_reading_role(&blk)
        elsif query.mutation?
          set_writing_role(&blk)
        elsif readonly_primary_forced?(context)
          set_writing_role_prevent_writes(&blk)
        else
          ::DatabaseSelector.instance.read_from_database(last_operations: last_operations, called_from: :platform_session, &blk)
        end
      end
    end

    def self.set_reading_role(&blk)
      ActiveRecord::Base.connected_to(role: :reading, &blk)
    end

    def self.set_writing_role(&blk)
      ActiveRecord::Base.connected_to(role: :writing, &blk)
    end

    def self.set_writing_role_prevent_writes(&blk)
      ActiveRecord::Base.connected_to(role: :writing, prevent_writes: true, &blk)
    end

    def self.readonly_forced?(context)
      context[:force_readonly]
    end

    def self.readonly_primary_forced?(context)
      context[:force_readonly_primary]
    end

    def self.setup_last_operations(context)
      if (request_token = context[:request_token])
        DatabaseSelector::LastOperations.from_token(request_token)
      elsif (session = context[:session])
        DatabaseSelector::LastOperations.from_session(session)
      end
    end
  end
end
