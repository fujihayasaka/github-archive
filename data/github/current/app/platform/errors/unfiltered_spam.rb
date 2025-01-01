# typed: true
# frozen_string_literal: true
module Platform
  module Errors
    class UnfilteredSpam < Platform::Errors::Internal
      MESSAGE_TEMPLATE = <<~MSG
      %{owner_type_name}.%{field_name} returned an ActiveRecord::Relation (of %{result_model_name}) which could have been filtered for spam with `.filter_spam_for(user)`, but it wasn't filtered.

      Usually, spam should be filtered from GraphQL so that the API response matches the web UI.

      If you meant to filter spam according to the viewer's permissions, add to the resolve function:

        your_relation.filter_spam_for(context[:viewer])

      If this field is exempt from spam filtering, or if you've implemented spam filtering another way, add a flag to skip this check:

        field :%{field_name}, ... do
          exempt_from_spam_filter_check
        end

      Unfiltered SQL:

        %{relation_sql}
      MSG

      def initialize(result, field_name:, owner_type_name:)
        message = MESSAGE_TEMPLATE % {
          result_model_name: result.klass.name,
          field_name: field_name,
          owner_type_name: owner_type_name,
          relation_sql: result.to_sql,
        }
        super(message)
      end
    end
  end
end
