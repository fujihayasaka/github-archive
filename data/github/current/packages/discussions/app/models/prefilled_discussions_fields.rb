# typed: true
# frozen_string_literal: true

# Public: Loads Discussion assocation objects for
#         pre-filling in the new Discussion based on query params.
#
class PrefilledDiscussionsFields
  extend T::Sig

  attr_reader :params, :repository, :user

  MAX_LABELS_FROM_PARAMS = 20

  # Public: Initialize a new PrefilledDiscussionsFields object.
  #
  # params - A StrongParams instance passed from a controller action.
  # repository - The current Repository, where an Discussion will exist.
  # user - The current User, responsible for the Discussion.
  #
  # Returns a PrefilledDiscussionsFields instance.
  sig do
    params(
      params: T.untyped,
      repository: T.untyped,
      user: T.untyped,
      can_create_announcements: T.untyped,
      can_label: T.untyped
    ).void
  end
  def initialize(params:, repository:, user:, can_create_announcements: false, can_label: false)
    @params = params
    @repository = repository
    @user = user
    @can_create_announcements = can_create_announcements
    @can_label = can_label
  end

  # Public: A title String from params.
  #
  # If params[:welcome_text] is true, returns the welcome title.
  # Else, reads from params[:title].
  #
  # Returns a String or nil.
  sig { returns(T.untyped) }
  def title
    return "Welcome to #{repository.name} Discussions!" if params[:welcome_text]

    params[:title] || template&.title
  end

  # Public: A body String from params.
  #
  # If neither :body nor :permalink is present, returns nil.
  #
  # If one of either is present, returns it. If both are present,
  # returns the :body value then :permalink value separated by a
  # newline.
  #
  # Returns a String or nil.
  sig { returns(T.untyped) }
  def body
    if params[:welcome_text]
      Discussion::WELCOME_BODY
    elsif params[:body] || params[:permalink]
      [params[:body], params[:permalink]].compact.join("\n\n")
    else
      nil
    end
  end

  # Public: A category slug from params.
  #
  # Validates that the passed in slug corresponds to a category on this
  # repo, and if the category is of the announcements flavor, makes sure
  # that the user is authorized to create a discussion of this flavor
  #
  # Returns a discussion cateogry or nil.
  sig { returns(T.untyped) }
  def category
    if params[:category].present?
      initial_category = repository.available_discussion_categories.find_by(
        slug: params[:category],
      )

      if initial_category.present?
        is_authorized_category = !initial_category.supports_announcements? || @can_create_announcements

        initial_category if is_authorized_category
      end
    end
  end

  # Public: A collection of Label records from the repository from query params.
  #
  # Will return up to MAX_LABELS_FROM_PARAMS records from the repository.
  #
  # Understands a comma-separated String, such as "&labels=foo,bar".
  #
  # Returns an Array[Label].
  sig { returns(T.untyped) }
  def labels
    return @labels if defined?(@labels)
    combined_labels = (labels_from_template + labels_from_params).uniq
    @labels = combined_labels.first(MAX_LABELS_FROM_PARAMS)
  end

  # Returns a hash of the leftover params that might correspond to discussion form fields
  sig { returns(T.untyped) }
  def structured_template_inputs
    params.except(:body, :category, :title, :labels)
  end

  private

  def template
    @template ||= repository.preferred_discussion_templates.for_slug(category&.slug)
  end

  def labels_from_params
    return [] unless @can_label
    names = params[:labels].to_s.split(",").first(MAX_LABELS_FROM_PARAMS).each(&:strip!).select(&:present?)
    return [] if names.empty?
    repository.labels.where(name: names).limit(MAX_LABELS_FROM_PARAMS).to_a
  end

  def labels_from_template
    return [] unless template.present?
    template.labels.to_a
  end
end
