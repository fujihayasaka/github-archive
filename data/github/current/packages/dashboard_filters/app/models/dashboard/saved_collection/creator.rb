# typed: true
# frozen_string_literal: true

class Dashboard::SavedCollection
  class Creator

    class Result
      attr_accessor :errors
      attr_reader :collection

      def initialize(collection:, errors: [])
        @collection = collection
        @errors = errors
      end

      def success?
        @errors.empty?
      end
    end

    def self.execute(dashboard:, name:, description:, saved_views: [], icon: nil, color: nil, protected_type: nil)
      new(
        dashboard: dashboard,
        name: name,
        description: description,
        saved_views: saved_views,
        icon: icon,
        color: color,
        protected_type: protected_type,
      ).execute
    end

    def initialize(dashboard:, name:, description:, saved_views: [], icon: nil, color: nil, protected_type: nil)
      @dashboard = dashboard
      @name = name
      @description = description
      @saved_views = saved_views
      @icon = icon
      @color = color
      @protected_type = protected_type
    end

    attr_reader :dashboard, :name, :saved_views, :description, :icon, :color, :protected_type

    def execute
      collection = Dashboard::SavedCollection.new(
        dashboard: dashboard,
        name: name,
      )

      collection.description = description if @description
      collection.icon = icon if @icon
      collection.color = color if @color
      collection.protected_type = protected_type if @protected_type

      errors = []
      Dashboard::SavedCollection.transaction do
        unless collection.save
          errors.concat(collection.errors.full_messages)
          raise ActiveRecord::Rollback
        end

        saved_views.each do |saved_view_input|
          saved_view = Dashboard::SavedView.new(
            saved_collection: collection,
            name: saved_view_input[:name],
            query: saved_view_input[:query],
          )

          saved_view.description = saved_view_input[:description] if saved_view_input.key?(:description)
          saved_view.icon = saved_view_input[:icon] if saved_view_input.key?(:icon)
          saved_view.color = saved_view_input[:color] if saved_view_input.key?(:color)

          unless saved_view.save
            errors.concat(saved_view.errors.full_messages)
            raise ActiveRecord::Rollback
          end
        end
      end

      Result.new(collection: collection, errors: errors)
    end
  end
end
