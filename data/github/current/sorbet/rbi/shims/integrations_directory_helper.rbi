# typed: true
# frozen_string_literal: true

module IntegrationsDirectoryHelper
  sig { params(owner: String, id: String, anchor: String).returns(String) }
  def stafftools_user_application_path(owner, id, anchor: ""); end

  sig { params(owner: String, id: String, anchor: String).returns(String) }
  def gh_stafftools_app_path(owner, id, anchor: ""); end
end
