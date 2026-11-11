# typed: true
# frozen_string_literal: true

class Issue::Loader::CurrentRepository < Issue::Loader::Base
  def initialize(context)
    @repository = context.repository
    @viewer = context.viewer
  end

  def self.load_for(context)
    super new(context)
  end

  def load
    models = [@repository]
    promises = [
      async_preload_attribute(models, :viewer_can_see_commenter_full_name, :async_viewer_can_see_commenter_full_name?, [@viewer]),
    ]
    Promise.all(promises).sync
  end
end
