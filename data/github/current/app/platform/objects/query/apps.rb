# typed: true
# frozen_string_literal: true

module Platform::Objects::Query::Apps
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    # This field should never be publicly exposed
    T.bind(self, T.class_of(Platform::Objects::Query))

    field :programmatic_access_bot, Objects::ProgrammaticAccessBot, null: true,
          description: "The underlying bot associated with PATs V2"
    def programmatic_access_bot; end
  end
end
