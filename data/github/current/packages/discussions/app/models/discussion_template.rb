# typed: true
# frozen_string_literal: true

class DiscussionTemplate
  attr_reader :repository, :config, :filename
  delegate :body, :user_inputs, :title, :errors, :valid?, to: :config
  alias :inputs :body

  sig { params(tree_entry: T.untyped).returns(T.untyped) }
  def self.from_tree_entry(tree_entry)
    config = DiscussionForms::TemplateConfig.new(
      input: tree_entry.data,
      path: tree_entry.path,
    ).load

    from_structured_config(
      config: config,
      repository: tree_entry.repository,
      filename: tree_entry.path
    )
  end

  sig { params(config: T.untyped, repository: T.untyped, filename: T.untyped).returns(T.untyped) }
  def self.from_structured_config(config:, repository:, filename:)
    template = new(
      repository: repository,
      config: config,
      filename: filename,
    )
    template
  end

  sig { params(repository: T.untyped, config: T.untyped, filename: T.untyped).void }
  def initialize(
    repository:,
    config:,
    filename: ""
  )
    @repository    = repository
    @config        = config
    @filename      = filename
  end

  sig { returns(T.untyped) }
  def category_slug
    return @category_slug if defined?(@category_slug)
    return @category_slug = nil unless DiscussionTemplates.valid_path?(filename)
    @category_slug = File.basename(filename, ".*").downcase
  end

  sig { returns(T.untyped) }
  def category
    return nil if category_slug.blank?
    @category ||= @repository.discussion_categories.find_by(slug: category_slug)
  end

  sig { returns(T.untyped) }
  def labels_string
    @labels_string ||= config.labels.join(", ")
  end

  sig { returns(T.untyped) }
  def labels
    @labels ||= prefilled_discussion_fields.labels
  end

  sig { returns(T.untyped) }
  def discussion
    @discussion ||= repository.discussions.build(labels: labels)
  end

  sig { returns(T.untyped) }
  def url
    DiscussionTemplateFormUrl.new(self).to_s
  end

  private

  def prefilled_discussion_fields
    @prefilled_issue_fields ||= PrefilledDiscussionsFields.new(
      params: { labels: labels_string },
      repository: repository,
      user: nil,
      can_label: true,
    )
  end

  class DiscussionTemplateFormUrl
    include UrlHelpers

    sig { params(template: T.untyped).void }
    def initialize(template)
      @template = template
    end

    sig { returns(T.untyped) }
    def to_s
      URI.join(GitHub.url, template_path).to_s
    end

    private

    def template_path
      new_discussion_path(
        @template.repository.owner,
        @template.repository,
        params: { category: @template.category_slug }
      )
    end
  end
end
