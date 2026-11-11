# typed: true
# frozen_string_literal: true

class Issue::Loader::LatestUserContentEdit < Issue::Loader::Base
  def initialize(context, models: [])
    @viewer = context.viewer
    @context = context
    @models = models
  end

  def self.load_for(context, models: [])
    super new(context, models: models)
  end

  # void as async_latest_user_content_edit internally sets the association
  def load
    return unless @models.any?
    Promise.all(
      @models.map do |model|
        # must be preloaded before calling
        next unless model.viewer_can_read_user_content_edits?(@viewer)
        model.async_latest_user_content_edit
      end
    ).sync
  end
end
