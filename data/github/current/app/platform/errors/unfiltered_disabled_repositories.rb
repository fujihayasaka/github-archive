# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class UnfilteredDisabledRepositories < Platform::Errors::Internal
      MESSAGE_TEMPLATE = <<~MSG
      %{owner_type_name}.%{field_name} returned an ActiveRecord::Relation (of %{result_model_name}) which could have been filtered for disabled repos with `.filter_spam_and_disabled_for(user)`, but it wasn't filtered.

      You need to filter out disabled repositories (like those which have been DMCA'd), by adding this to the resolve function:

        your_relation.filter_spam_and_disabled_for(context[:viewer])

      Unfiltered SQL:

        %{relation_sql}
      MSG

      def initialize(field, result, ctx)
        message = MESSAGE_TEMPLATE % {
          result_model_name: result.klass.name,
          field_name: field.name,
          owner_type_name: field.owner_type.name,
          relation_sql: result.to_sql,
        }
        super(message)
      end
    end
  end
end
