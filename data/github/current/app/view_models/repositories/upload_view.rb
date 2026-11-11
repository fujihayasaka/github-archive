# typed: true
# frozen_string_literal: true

class Repositories::UploadView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :branch
  attr_reader :path
  attr_reader :parent_repo
  attr_reader :forked_repo
  attr_reader :target_branch
  attr_reader :quick_pull

  include WebCommit::PreviewViewMethods

  # Override WebCommit::PreviewViewMethods#new_file?
  def new_file?
    false
  end

  # Override WebCommit::PreviewViewMethods#quick_pull_field_value
  #
  # WebCommit::PreviewViewMethods#quick_pull_field_value builds this field
  # value from the `quick_pull` attribute, and it expects it to be a String.
  # But in this view, `quick_pull` is a Boolean, so we use a different formula
  # for prefilling this field.
  def quick_pull_field_value
    quick_pull_base || quick_pull_default
  end

  def binary_path
    return "" unless path
    Base64.strict_encode64(path.join("/"))
  end
end
