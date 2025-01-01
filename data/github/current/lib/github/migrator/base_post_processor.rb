# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class BasePostProcessor
      # Used for batch loading associations
      BATCH_SIZE = 1000

      def initialize(options = nil)
        @post_processor_options = options || {}
        @current_migration      = @post_processor_options[:current_migration]
        @migration_path         = @post_processor_options[:migration_path]
        @user_content_rewriter  = \
          @post_processor_options[:user_content_rewriter] ||
          UserContentRewriter.new(options)
      end

      # Public: Implement in subclasses to process models.
      #
      # model      - Instance of github app model.
      # attributes - Hash of attributes for model.
      # actor      - Instance of a User.
      def process(model, attributes, actor)
        # noop
      end

      # Public: associations that should be included when loading the model
      # Should be overridden in subclasses
      #
      # Returns an array
      def joins
        []
      end

      private

      # Internal: MigratableResource scope for this migration.
      #
      # Returns an ActiveRecord scope.
      attr_reader :current_migration

      # Internal: The migration staging path.
      #
      # Returns a String or Pathname.
      attr_reader :migration_path

      # Internal: The options hash for this post processor instance.
      #
      # Returns a Hash.
      attr_reader :post_processor_options

      # Internal: Instance of UserContentRewriter for updating urls and mentions
      # in issue/pr/comment bodies.
      #
      # Returns a UserContentRewriter
      attr_reader :user_content_rewriter

      # Internal: Get the last part of a url.
      #
      # Returns a String.
      def last_part_of_url(url)
        return unless url

        url.split("/").last
      end

      # Internal: Updates the body attribute of a model and creates references to
      # other refferables. See `Referrer` module.
      #
      # Returns the provided model
      def update_body_with_references(model)
        klass = model.class
        klass.reference_mentions_callback.before_save(model)

        if model.has_attribute?(:compressed_body)
          model.update_columns(body: model.body, compressed_body: model.body) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
        else
          model.update_columns(body: model.body)
        end

        klass.reference_mentions_callback.after_save(model)

        # If body was the only dirty attribute, mark the record as persisted.
        if model.changed == ["body"]
          model.changes_applied
        end

        model
      end

      def rewrite_comment(comment)
        comment.body = user_content_rewriter.process(comment)
        return unless comment.changed?
        update_body_with_references(comment)
      end
    end
  end
end
