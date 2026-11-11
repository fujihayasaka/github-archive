# typed: false
# frozen_string_literal: true

module DeveloperHelper
  def context_settings_path
    opts = { anchor: "github-developer-program" }
    if @account && @account.organization?
      "/organizations/#{@account}/settings#github-developer-program"
    else
      settings_user_profile_path(opts)
    end
  end
end
