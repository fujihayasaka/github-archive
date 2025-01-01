# typed: strict
# frozen_string_literal: true

module UploadContainer::UploadContainerDependency
  extend T::Helpers

  abstract!

  sig { abstract.params(user_id: Integer, guid: String, use_new_url: T::Boolean).returns(String) }
  def private_asset_url(user_id, guid, use_new_url); end
end
