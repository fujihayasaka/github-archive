# typed: true
# frozen_string_literal: true

class Issue::Loader::ProjectCards < Issue::Loader::Base
  def initialize(context, project_card_ids: [])
    @context = context
    @project_card_ids = project_card_ids
  end

  def self.load_for(context, project_card_ids: [])
    super new(context, project_card_ids: project_card_ids)
  end

  def self.preload_for(context, project_cards: [])
    new(context).preload(project_cards)
  end

  def load
    return {} unless @project_card_ids.any?

    ProjectCard.strict_loading.
      where(id: @project_card_ids).
      index_by(&:id)
  end

  def preload(project_cards)
    return unless project_cards.any?

    track_execution_time do
      Promise.all([
        async_preload_attribute(project_cards, :url, :async_url),
      ]).sync
    end
  end
end
