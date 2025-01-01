# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

module Platform::Objects::Query::CommunityAndSafety
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    field :code_of_conduct, Objects::CodeOfConduct, description: "Look up a code of conduct by its key", null: true do
      argument :key, String, "The code of conduct's key", required: true
    end

    def code_of_conduct(**arguments)
      ::CodeOfConduct.find_by_key(arguments[:key])
    end

    field :codes_of_conduct, [Objects::CodeOfConduct, null: true], description: "Look up a code of conduct by its key", null: true

    def codes_of_conduct
      ::CodeOfConduct.recommended
    end

    field :license, Objects::License, description: "Look up an open source license by its key", null: true do
      argument :key, String, "The license's downcased SPDX ID", required: true
    end

    def license(**arguments)
      ::License.find_by_key(arguments[:key])
    end

    field :licenses, [Objects::License, null: true], description: "Return a list of known open source licenses", null: false

    def licenses
      ::License.all
    end
  end
end
