# typed: false
# frozen_string_literal: true

module Platform
  module Helpers
    class ProjectCards
      def initialize(parent, arguments, context)
        @parent = parent
        @arguments = arguments
        @context = context
      end

      def connection_for_cards(cards, field:, max_page_size:, parent:)
        connection_arguments = {
          first: @arguments[:first],
          last: @arguments[:last],
          after: @arguments[:after],
          before: @arguments[:before],
          arguments: @arguments,
          field: field,
          max_page_size: max_page_size,
          parent: parent,
          context: @context
        }
        case @parent
        when Project, ProjectColumn
          Platform::ConnectionWrappers::ProjectCardsArrayConnection.new(
            cards,
            **connection_arguments
          )
        else
          Platform::ConnectionWrappers::ArrayWrapper.new(
            cards,
            **connection_arguments
          )
        end
      end

      def connection(field: nil, max_page_size: nil, parent: nil)
        case @parent
        when Project
          include_params = card_include_params
          if include_params[:include_pending] && include_params[:include_triaged]
            cards = @parent.cards
            cards = archived_filter(cards)
            connection = connection_for_cards(cards, field: field, max_page_size: max_page_size, parent: parent)
            Promise.resolve(connection)
          else
            cards = @parent.cards
            cards = cards.filtered(**include_params)
            cards = archived_filter(cards)
            connection = connection_for_cards(cards, field: field, max_page_size: max_page_size, parent: parent)
            Promise.resolve(connection)
          end
        when ProjectColumn
          cards = @parent.cards.by_priority
          cards = archived_filter(cards)
          connection = connection_for_cards(cards, field: field, max_page_size: max_page_size, parent: parent)
          Promise.resolve(connection)
        when ::Issue
          @parent.async_repository.then do |repo|
            repo.async_owner.then do
              if @context[:permission].can_list_projects?(repo)
                cards = @parent.visible_cards_for(@context[:viewer])
                cards = archived_filter(cards)
              else
                cards = ArrayWrapper.new([])
              end
              connection_for_cards(cards, field: field, max_page_size: max_page_size, parent: parent)
            end
          end
        when ::PullRequest
          @parent.async_issue.then do |issue|
            issue.async_repository.then do |repo|
              repo.async_owner.then do
                next ProjectCard.none unless @context[:permission].can_list_projects?(repo)

                cards = issue.visible_cards_for(@context[:viewer])
                cards = archived_filter(cards)
                connection_for_cards(cards, field: field, max_page_size: max_page_size, parent: parent)
              end
            end
          end
        end
      end

      def total_count
        case @parent
        when Project
          cards = @parent.cards.filtered(**card_include_params)
          cards = archived_filter(cards)
          cards.size
        when ProjectColumn
          archived_filter(@parent.cards).size
        when ::Issue
          @parent.async_repository.then do |repo|
            repo.async_owner.then do
              archived_filter(@parent.visible_cards_for(@context[:viewer])).size
            end
          end
        when ::PullRequest
          @parent.async_issue.then do |issue|
            issue.async_repository.then do |repo|
              repo.async_owner.then do
                archived_filter(issue.visible_cards_for(@context[:viewer])).size
              end
            end
          end
        end
      end

      def archived_filter(cards)
        return cards unless @arguments.key?(:archived_states)

        if @arguments[:archived_states].sort == [:archived, :not_archived]
          cards
        elsif @arguments[:archived_states].include?(:archived)
          cards.archived
        elsif @arguments[:archived_states].include?(:not_archived)
          cards.not_archived
        end
      end

      def card_include_params
        if @context[:backwards_compatibility_pending]
          {
            include_pending: true,
            include_triaged: false,
          }
        else
          {
            include_pending: @arguments.key?(:include_pending) ? @arguments[:include_pending] : true,
            include_triaged: @arguments.key?(:include_triaged) ? @arguments[:include_triaged] : true,
          }
        end
      end
    end
  end
end
