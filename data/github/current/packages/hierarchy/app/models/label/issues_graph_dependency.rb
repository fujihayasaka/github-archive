# typed: false
# frozen_string_literal: true

# methods to be mixed into the Label model
module Label::IssuesGraphDependency
  extend ActiveSupport::Concern

  # Public: Convert a given label into a hash that the issues-graph service accepts as the "key" of a LabelV2 on
  # the graph.
  #
  # Returns a Hash.
  def to_hierarchy_model_key
    {
      ownerId: repository.owner_id,
      itemId: id,
    }
  end

  # Public: Convert a given label into a hash that the issues-graph service accepts as a representation of a
  # LabelV2 on the graph.
  #
  # Returns a Hash.
  def to_hierarchy_model
    {
      key: to_hierarchy_model_key,
      name: name,
      nameHtml: "#{name_html}",
      url: url,
      color: color,
      repoId: repository_id,
    }
  end
end
