# typed: true
# frozen_string_literal: true

class Releases::TagInfoComponent < ApplicationComponent
  attr_reader :tag_as_release, :current_repository, :view

  def initialize(tag_as_release, current_repository, view, writable:, deletable:)
    @tag_as_release = tag_as_release
    @current_repository = current_repository
    @view = view
    @writable = writable
    @deletable = deletable
  end

  def writable?
    @writable
  end

  def deletable?
    @deletable
  end

  def enable_delete_option?
    tag_as_release.new_record? && deletable?
  end

  def target
    @tag_as_release.tag_target
  end

  memoize def delete_dialog_id
    "delete_release_#{SecureRandom.hex(4)}_#{tag_as_release.id || tag_as_release.tag_name.gsub(/[\.:#]/, "_")}"
  end
end
