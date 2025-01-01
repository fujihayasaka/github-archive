# typed: true
# frozen_string_literal: true

class SpeedscopeController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:file]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  SPEEDSCOPE_ROOT = Rails.root.join("vendor/speedscope").to_s

  protect_from_forgery except: :file

  # CAP not required, employee only tool
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :append_csp, only: :index
  before_action :employee_only, if: -> { !GitHub.enterprise? }
  before_action :site_admin_only, if: -> { GitHub.enterprise? }

  def index
    nonce = SecureHeaders.content_security_policy_script_nonce(request)
    render body: File.read(files["index.html"]).gsub(/<script/, "<script nonce=\"#{nonce}\""),
      content_type: "text/html"
  end

  def file # rubocop:todo GitHub/UseRestfulActions
    path = params[:filename] + File.extname(request.path)

    if files.include?(path)
      render file: files[path], layout: false
    else
      render_404
    end
  end

  private

  def files # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_files ||= Dir[SPEEDSCOPE_ROOT + "/*"].map do |file|
      [File.basename(file), file]
    end.to_h
  end

  def append_csp
    SecureHeaders::append_content_security_policy_directives(
      request,
      script_src: ["'self'", SecureHeaders.content_security_policy_script_nonce(request), "'strict-dynamic'"],
      style_src: %w('self' fonts.googleapis.com),
      font_src: %w(fonts.gstatic.com)
    )
  end
end
