# typed: true
# frozen_string_literal: true

class Site::SecurityController < Site::BaseController
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index, :txt]

  SECURITY_TXT_EXPIRES = 30.days

  stylesheet_bundle "security"

  def index
    render "site/security/index"
  end

  def txt # rubocop:todo GitHub/UseRestfulActions
    render plain: <<~EOF
      Contact: https://hackerone.com/github
      Acknowledgments: https://hackerone.com/github/hacktivity
      Preferred-Languages: en
      Canonical: https://github.com/.well-known/security.txt
      Policy: https://bounty.github.com
      Hiring: https://github.careers
      Expires: #{(Time.now.utc + SECURITY_TXT_EXPIRES).strftime("%FT%Tz")}
    EOF
  end
end
