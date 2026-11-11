# typed: strict
# frozen_string_literal: true

module UploadContainer
  module UserUploadContainerDependency
    include UploadContainerDependency

    sig { override.params(user_id: Integer, guid: String, use_new_url: T::Boolean).returns(String) }
    def private_asset_url(user_id, guid, use_new_url)
      return "#{GitHub.url}/user-attachments/assets/#{guid}" if use_new_url
      "#{GitHub.url}/settings/replies/assets/#{user_id}/#{guid}"
    end
  end
end
