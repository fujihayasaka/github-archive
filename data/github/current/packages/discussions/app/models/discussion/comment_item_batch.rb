# typed: true
# frozen_string_literal: true

class Discussion
  # Helper model to respond to requests from one of the <batched-deferred-content> elements on the discussions#show
  # page. These are used to render pieces of deferred content for the Discussion body itself and for each
  # DiscussionComment on the page.
  #
  # These elements generate a POST request with a request body containing JSON with this structure:
  #
  #   { items: { "item-0": { discussion_id: 12 }, "item-1": { comment_id: 123 } } }
  #
  # The response is expected to be JSON with this structure:
  #
  #   { "item-0": "<HTML fragment for discussion body>", "item-1": "<HTML fragment for comment>" }
  #
  # Example of using this class to facilitate handling this pattern:
  #
  #   before_filter :require_discussion, only: [:some_action]
  #
  #   def some_action
  #     item_batch = Discussion::CommentItemBatch.new(current_repository, params)
  #     keyed_responses = ActiveRecord::Base.connected_to(role: :reading) do
  #       item_batch.map_inputs do |handler|
  #         handler.discussion do
  #           # Render something with discussion
  #         end
  #
  #         handler.comment do |comment|
  #           # Render something with comment
  #         end
  #       end
  #     end
  #
  #     respond_to do |format|
  #       format.json do
  #         render json: keyed_responses
  #       end
  #     end
  #  end
  #
  class CommentItemBatch
    sig { params(repository: T.untyped, params: T.untyped).void }
    def initialize(repository, params)
      @repository = repository
      @items = params.require(:items).permit!.to_h
      @discussion_number = params[:number]
    end

    # Extract "comment_id" values from all items in the item hash.
    #
    # Returns an Array containing the comment IDs as Strings.
    sig { returns(T.untyped) }
    def item_comment_ids
      return @item_comment_ids if defined?(@item_comment_ids)
      @item_comment_ids = @items.values.map { |input| input[:comment_id] }.reject(&:nil?)
    end

    # Efficiently load DiscussionComment records corresponding to each batch item with a "comment_id". Note that invalid
    # comment_id values, or IDs of comments that do not belong to the current repository, will be omitted from the
    # resulting Hash.
    #
    # Returns a Hash mapping integer IDs to loaded DiscussionComment records.
    sig { returns(T.untyped) }
    def comments_by_id
      return @comments_by_id if defined?(@comments_by_id)
      @comments_by_id = @repository.discussion_comments.where(id: item_comment_ids).index_by(&:id)
    end

    # Return the collection of DiscussionComments successfully loaded from requested :comment_ids.
    sig { returns(T.untyped) }
    def comments
      comments_by_id.values
    end

    # Return the collection of unique IDs of DiscussionComments successfully loaded from requested :comment_ids. Note
    # that this will be a subset of :item_comment_ids.
    sig { returns(T.untyped) }
    def comment_ids
      comments_by_id.keys
    end

    # Extract "discussion_id" values from all items in the item hash.
    #
    # Returns an Array containing the discussion IDs as Strings.
    sig { returns(T.untyped) }
    def item_discussion_ids
      return @item_discussion_ids if defined?(@item_discussion_ids)
      @item_discussion_ids = @items.values.map { |input| input[:discussion_id] }.reject(&:nil?)
    end

    # Efficiently load Discussion records corresponding to each batch item with a "discussion". Note that invalid
    # discussion_id values, or IDs of discussion that do not belong to the current repository, will be omitted from the
    # resulting Hash.
    #
    # Returns a Hash mapping integer IDs to loaded Discussion records.
    sig { returns(T.untyped) }
    def discussions_by_id
      return @discussions_by_id if defined?(@discussions_by_id)

      @discussions_by_id = @repository.discussions.where(id: item_discussion_ids).index_by(&:id)
    end

    # Return the collection of Discussions successfully loaded from requested :discussion_ids.
    sig { returns(T.untyped) }
    def discussions
      discussions_by_id.values
    end

    # Return the collection of unique IDs of Discussions successfully loaded from requested :discussion_ids. Note
    # that this will be a subset of :item_discussion_ids.
    sig { returns(T.untyped) }
    def discussion_ids
      discussions_by_id.keys
    end

    # Return the collection of model objects in this batch.
    sig { returns(T.untyped) }
    def models
      discussions + comments
    end

    # Handle each requested item individually. An associated block will be called with a handler which may be used to
    # customize behavior for each kind of expected item input. The "discussion" block will be used for the item mapped
    # to the Discussion itself. Valid "comment" blocks are invoked with the corresponding loaded DiscussionComment
    # instance. If the commit ID is not valid, no blocks will be triggered and an empty string (`""`) will be used as
    # its output.
    #
    # Usage:
    #
    #   item_batch.map_inputs do |handler|
    #     # Invoked for the `{ discussion_id: 12 }` input
    #     handler.discussion { "..." }
    #
    #     # Invoked for each `{ comment_id: 123 }` input that maps to a valid DiscussionComment
    #     handler.comment { |comment| "..." }
    #   end
    #
    # Returns a Hash mapping String item keys corresponding to the items parsed from the request body to the results of
    # the matching handler block invoked for each item's input arguments.
    sig { returns(T.untyped) }
    def map_inputs
      @items.transform_values do |input|
        comment_id = Integer(input[:comment_id], exception: false)
        discussion_id = Integer(input[:discussion_id], exception: false)
        handler = if comment_id
          comment = comments_by_id[comment_id]
          if comment
            CommentHandler.new(comment, input[:button_only])
          end
        elsif discussion_id
          discussion = discussions_by_id[discussion_id]
          if discussion
            DiscussionHandler.new(discussion)
          end
        end
        handler ||= ItemHandler.new
        yield handler
        handler.result
      end
    end

    # Superclass of the handlers yielded to the block given to a #map_inputs call. Also used as-is for inputs with an
    # invalid comment ID.
    class ItemHandler
      sig { void }
      def initialize
        @result = ""
      end

      attr_reader :result

      sig { returns(T.untyped) }
      def comment
        # Default behavior: do not invoke associated coroutine or modify @result
      end

      sig { returns(T.untyped) }
      def discussion
        # Default behavior: do not invoke associated coroutine or modify @result
      end
    end

    # Handler subclass used to respond to items with inputs of the form `{discussion_id: 123}`.
    class DiscussionHandler < ItemHandler
      sig { params(discussion: T.untyped).void }
      def initialize(discussion)
        super()
        @discussion = discussion
      end

      sig { returns(T.untyped) }
      def discussion
        @result = yield @discussion
      end
    end

    # Handler subclass used to respond to items with inputs of the form `{comment_id: 123}` when 123 is the ID of a
    # valid DiscussionComment associated with this batch's discussion.
    class CommentHandler < ItemHandler
      sig { params(comment: T.untyped, button_only: T.untyped).void }
      def initialize(comment, button_only)
        super()
        @comment = comment
        @button_only = button_only && @comment.nested?
      end

      sig { returns(T.untyped) }
      def comment
        @result = yield @comment
      end

      sig { returns(T.untyped) }
      def button_only?
        @button_only
      end
    end
  end
end
