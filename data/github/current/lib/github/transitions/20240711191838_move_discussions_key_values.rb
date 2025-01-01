# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveDiscussionsKeyValues < MoveKeyValuesBase
      sig { override.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class
        Discussions::Kv::DataStore
      end

      iterate_key_values [
        "read:discussion:%", # packages/discussions/app/models/discussion.rb
        "repositories.%.discussion\\_categories.category\\_limit", # packages/discussions/app/models/discussion_category/limit_override.rb
        "discussion\\_category\\_%\\_deleting", # packages/discussions/app/models/discussion_category.rb
        "discussion-timeline-items-per-page", # packages/discussions/app/models/discussion_timeline/paginated_render_context.rb
        "discussions-view-%", # packages/discussions/app/models/repository/discussions_dependency.rb
        "discussion-ann:%", # packages/discussions/app/models/user/discussions_dependency.rb
        "discussion-private-repo-ann:%", # packages/discussions/app/models/user/discussions_dependency.rb
      ]
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(cleanup))

  GitHub::Transitions::MoveDiscussionsKeyValues.new(args).run
end
