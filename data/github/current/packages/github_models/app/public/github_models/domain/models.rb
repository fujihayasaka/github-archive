# typed: strict
# frozen_string_literal: true

module GitHubModels
  class Domain
    class Models < GH::Domain::Base
      include GitHub::Memoizer

      # Public: Returns the MySQL cluster used for replication delay for ElasticSearch.
      sig { returns Symbol }
      def mysql_cluster_name
        Model.cluster_name
      end

      # Public: Look up a model by its original name, its unique key, or its ID. Returns nil when it's not found.
      sig do
        params(
          original_name: T.nilable(String),
          slug: T.nilable(String),
          id: T.nilable(T.any(Integer, String))
        ).returns(T.nilable(IModel))
      end
      def find(original_name: nil, slug: nil, id: nil)
        if id.present?
          Model.find_by(id: id)
        elsif slug.present?
          Model.find_by(slug: slug)
        elsif original_name.present?
          # This is OK because the table has <50 rows and will at most grow to one or two thousand.
          # rubocop:disable GitHub/DoNotUseLower
          Model.find_by("LOWER(original_name) = LOWER(?)", original_name)
        end
      end

      # Public: Look up many models at once.
      sig do
        params(
          slugs: T::Array[String],
          visibilities: T::Array[T.any(String, Symbol)],
          ids: T::Array[T.any(Integer, String)],
          publicly_visible_only: T::Boolean,
          featured_only: T::Boolean,
          slugs_to_exclude: T::Array[String],
          order: ModelOrder,
          limit: T.nilable(Integer)
        ).returns(T::Array[IModel])
      end
      def find_many(slugs: [], visibilities: [], ids: [], publicly_visible_only: false, featured_only: false, slugs_to_exclude: [], order: ModelOrder::Slug, limit: nil)
        scope = Model.order_by(order)
        scope = scope.where(slug: slugs) if slugs.any?
        scope = scope.where.not(slug: slugs_to_exclude) if slugs_to_exclude.any?
        scope = scope.where(id: ids) if ids.any?
        scope = scope.where(visibility: visibilities) if visibilities.any?
        scope = scope.publicly_visible if publicly_visible_only
        scope = scope.featured if featured_only
        scope = scope.limit(limit) if limit
        scope.to_a
      end

      # Public: Look up a model by its slug or ID, and raise an exception if it's not found.
      sig { params(slug: T.nilable(String), id: T.nilable(T.any(Integer, String))).returns(IModel) }
      def find!(slug: nil, id: nil)
        if slug.present?
          Model.find_by!(slug: slug)
        elsif id.present?
          Model.find(id)
        else
          raise ArgumentError.new("Model slug or ID is required for lookup")
        end
      end

      # Public: Check if the given user has permission to see a model, as specified by its registry and name.
      sig { params(user: T.nilable(::User), registry: String, name: String).returns(T::Boolean) }
      def can_view?(user:, registry:, name:)
        Model.can_view?(user: user, registry: registry, name: name)
      end

      # Public: Given a model's unique slug, determine its registry and name.
      sig { params(slug: String).returns(T.nilable([String, String])) }
      def registry_and_name_from_slug(slug)
        Model.registry_and_name_from_slug(slug)
      end

      # Public: Based on the model registry and model name, determine what the unique slug for that model would be.
      sig { params(registry: String, name: String).returns(String) }
      def slug_for(registry:, name:)
        Model.slug_for(registry: registry, name: name)
      end

      # Public: Hit external APIs to look up a model's details and its schema.
      sig do
        params(
          registry: String,
          model_name: String,
          version: String,
          ai_studio_client: T.nilable(AzureAiStudioClient),
          schema_client: T.nilable(AzureAiModelSchemaClient)
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def fetch_from_api(registry:, model_name:, version:, ai_studio_client: nil, schema_client: nil)
        Model.fetch_value(
          registry: registry,
          model_name: model_name,
          version: version,
          ai_studio_client: ai_studio_client,
          schema_client: schema_client,
        )
      end

      # Public: Insert a new model record in the database or update an existing one that has the given slug.
      sig { params(slug: String, attrs: T::Hash[T.any(String, Symbol), T.untyped]).returns(IModel) }
      def upsert(slug, attrs)
        model = Model.find_by(slug: slug) || Model.new(slug: slug)
        model.update!(attrs)
        model
      end

      # Public: Change a model's popularity score. Returns a Boolean indicating success.
      sig { params(model: IModel, popularity: T.any(Integer, Float)).returns(T::Boolean) }
      def update_popularity(model, popularity)
        raise NoMethodError.new("#{model.class.name} does not have #update method") unless model.respond_to?(:update)
        slug = model.slug
        attrs = { popularity: popularity }
        T.unsafe(model).update(attrs)
      end

      # Public: Change a model's visibility. Raises an error if the update fails.
      sig { params(model: IModel, visibility: T.any(String, Symbol)).void }
      def update_visibility(model, visibility)
        unless model.respond_to?(:update!)
          raise NoMethodError.new("#{model.class.name} does not have #update! method")
        end
        slug = model.slug
        attrs = { visibility: visibility }
        T.unsafe(model).update!(attrs)
      end

      # Public: Wipe the popularity score for the given models. Returns the number of records updated.
      sig { params(models: T::Array[IModel]).returns(Integer) }
      def reset_popularity(models)
        slugs = models.map(&:slug)
        attrs = { popularity: 0 }
        Model.where(slug: slugs).update_all(attrs)
      end

      # Public: Delete a model.
      sig { params(model: IModel).returns(T::Boolean) }
      def destroy(model)
        return false unless model.respond_to?(:destroy)
        old_slug = model.slug
        T.unsafe(model).destroy
        model.destroyed?
      end

      # Public: Return the possible values for a model's visibility.
      sig { returns T::Array[T.any(String, Symbol)] }
      def visibilities
        Model.visibilities.keys
      end
    end
  end
end
