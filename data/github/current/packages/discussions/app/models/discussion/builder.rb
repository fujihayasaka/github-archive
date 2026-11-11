# typed: true
# frozen_string_literal: true

class Discussion
  class Builder
    attr_reader :user, :repository

    sig { params(user: T.untyped, repository: T.untyped).void }
    def initialize(user:, repository:)
      @user = user
      @repository = repository
    end

    sig { params(discussion_params: T.untyped, discussion_form_params: T.untyped).returns(T.untyped) }
    def build(discussion_params:, discussion_form_params: nil)
      label_ids = discussion_params.fetch(:labels, []).reject(&:blank?)
      discussion = Discussion.new(discussion_params.except(:labels, :poll_attributes))
      discussion.repository = repository
      discussion.user = user

      if discussion.category&.supports_polls?
        discussion.build_poll(discussion_params[:poll_attributes])
      end

      can_label = discussion.labelable_by?(user)

      if label_ids.any? && can_label
        labels = Issues.domain.labels.by_repository_and_normalized_ids(repository_id: repository.id, label_ids:)
        discussion.labels = T.cast(labels, T::Array[Label])
      end

      if discussion.template.present? && discussion.template.valid?
        build_from_template(
          discussion: discussion,
          discussion_form_params: discussion_form_params,
          can_label: can_label,
        )
      end

      discussion
    end

    private

    def build_from_template(discussion:, discussion_form_params:, can_label:)
      template = discussion.template
      label_names = template.labels.map(&:name)

      if label_names.present? && !can_label
        labels = Issues.domain.labels.by_repository_and_names(repository_id: repository.id, names: label_names)
        discussion.labels = T.cast(labels, T::Array[Label])
      end

      builder = StructuredTemplates::BodyBuilder.new(
        template: template,
        form_params: discussion_form_params,
        templatable: discussion,
      )

      if builder.valid?
        discussion.body = builder.to_markdown
        discussion.created_from_category_template = true
      end
    end
  end
end
